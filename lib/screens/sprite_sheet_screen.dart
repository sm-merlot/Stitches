import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../models/snippet.dart';
import '../providers/editor_provider.dart';
import '../services/sprite_importer.dart';
import '../widgets/sprite_sheet_painter.dart';

// ── Strip draw state ──────────────────────────────────────────────────────────

enum _StripDrawState { idle, drawing }

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen sprite sheet importer.
///
/// The user opens an image, crops the sprite region, optionally draws palette
/// strip regions, and adds the result to the current pattern's snippet library
/// via "Add to Snippets".
///
/// Pops with `true` if at least one snippet was added (so the caller can
/// open the snippets panel automatically), or `false` otherwise.
class SpriteSheetScreen extends ConsumerStatefulWidget {
  /// If provided, the image at this path is loaded automatically on open,
  /// skipping the file-picker step.
  final String? imagePath;

  const SpriteSheetScreen({super.key, this.imagePath});

  @override
  ConsumerState<SpriteSheetScreen> createState() => _SpriteSheetScreenState();
}

class _SpriteSheetScreenState extends ConsumerState<SpriteSheetScreen> {
  // ── Image ──────────────────────────────────────────────────────────────────
  Uint8List? _imageBytes;
  img.Image? _image;

  // ── View transform ──────────────────────────────────────────────────────────
  // Transform: screenPos = imagePos * _zoom + _pan
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  bool _autoFit = true; // recomputed in LayoutBuilder until first interaction

  // Saved on each LayoutBuilder pass so gesture handlers can reference it.
  Size _containerSize = Size.zero;

  // ── Gesture tracking ────────────────────────────────────────────────────────
  int _pointerCount = 0;
  double _lastScale = 1.0;
  Offset? _lastFocalPoint;

  // ── Crop selection ──────────────────────────────────────────────────────────
  Offset? _cropStart; // image coordinates
  Offset? _cropEnd;   // image coordinates

  // ── Palette strip drawing ───────────────────────────────────────────────────
  _StripDrawState _stripState = _StripDrawState.idle;
  Offset? _stripStart;
  Offset? _stripEnd;
  final List<Rect> _confirmedStrips = [];
  final List<List<Color>> _detectedStripColours = [];
  bool _showRecropWarning = false;

  // ── Preview ──────────────────────────────────────────────────────────────────
  Uint8List? _cropPreviewBytes;

  // ── Other ───────────────────────────────────────────────────────────────────
  int _mergeThreshold = 0;
  late final TextEditingController _nameCtrl;
  int _addedCount = 0;
  bool _importing = false;

  bool get _hasCrop => _cropStart != null && _cropEnd != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Sprite 1');
    if (widget.imagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadImageFromPath(widget.imagePath!));
    }
  }

  Future<void> _loadImageFromPath(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not decode image')),
        );
      }
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _image = decoded;
      _autoFit = true;
      _cropStart = null;
      _cropEnd = null;
      _cropPreviewBytes = null;
      _stripState = _StripDrawState.idle;
      _stripStart = null;
      _stripEnd = null;
      _confirmedStrips.clear();
      _detectedStripColours.clear();
      _showRecropWarning = false;
      _addedCount = 0;
      _nameCtrl.text = 'Sprite 1';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Transform helpers ────────────────────────────────────────────────────────

  /// Fit the image inside [containerSize] with letterboxing, centred.
  void _computeFit(Size containerSize) {
    if (_image == null || containerSize == Size.zero) return;
    _zoom = min(
      containerSize.width / _image!.width,
      containerSize.height / _image!.height,
    );
    _pan = Offset(
      (containerSize.width - _image!.width * _zoom) / 2,
      (containerSize.height - _image!.height * _zoom) / 2,
    );
  }

  /// Ensures the transform is initialised before a gesture handler runs.
  void _ensureFit() {
    if (_autoFit && _image != null && _containerSize != Size.zero) {
      _computeFit(_containerSize);
      _autoFit = false;
    }
  }

  /// Apply a zoom [factor] around [focalScreen] (screen coordinates).
  void _applyZoom(double factor, Offset focalScreen) {
    final newZoom = (_zoom * factor).clamp(0.25, 40.0);
    final sf = newZoom / _zoom;
    setState(() {
      _pan = focalScreen + (_pan - focalScreen) * sf;
      _zoom = newZoom;
    });
  }

  /// Convert screen coordinates → image pixel coordinates.
  Offset _toImage(Offset screen) => (screen - _pan) / _zoom;

  /// Regenerates [_cropPreviewBytes] from the current crop region.
  void _refreshCropPreview() {
    if (!_hasCrop || _image == null) {
      _cropPreviewBytes = null;
      return;
    }
    final crop = Rect.fromPoints(_cropStart!, _cropEnd!).intersect(
      Rect.fromLTWH(0, 0, _image!.width.toDouble(), _image!.height.toDouble()),
    );
    if (crop.isEmpty) {
      _cropPreviewBytes = null;
      return;
    }
    final cropped = img.copyCrop(
      _image!,
      x: crop.left.round(),
      y: crop.top.round(),
      width: crop.width.round().clamp(1, _image!.width),
      height: crop.height.round().clamp(1, _image!.height),
    );
    _cropPreviewBytes = Uint8List.fromList(img.encodePng(cropped));
  }

  // ── Image loading ────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final Uint8List bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      return;
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not decode image')),
        );
      }
      return;
    }

    setState(() {
      _imageBytes = bytes;
      _image = decoded;
      _autoFit = true;
      _cropStart = null;
      _cropEnd = null;
      _cropPreviewBytes = null;
      _stripState = _StripDrawState.idle;
      _stripStart = null;
      _stripEnd = null;
      _confirmedStrips.clear();
      _detectedStripColours.clear();
      _showRecropWarning = false;
      _addedCount = 0;
      _nameCtrl.text = 'Sprite 1';
    });
  }

  // ── Gesture handlers ─────────────────────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _ensureFit();
    final factor = event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12;
    _applyZoom(factor, event.localPosition);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _ensureFit();
    _lastScale = 1.0;
    _lastFocalPoint = d.localFocalPoint;

    if (_pointerCount == 1) {
      final imgPos = _toImage(d.localFocalPoint);
      if (_stripState == _StripDrawState.drawing) {
        // Drawing a palette strip.
        setState(() {
          _stripStart = imgPos;
          _stripEnd = imgPos;
        });
      } else {
        // Drawing the crop region; warn if strips already exist.
        if (_confirmedStrips.isNotEmpty) {
          setState(() => _showRecropWarning = true);
        } else {
          setState(() {
            _cropStart = imgPos;
            _cropEnd = imgPos;
          });
        }
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final focal = d.localFocalPoint;

    if (_pointerCount >= 2) {
      // Multi-touch: zoom around focal point + pan.
      final scaleDelta = d.scale / _lastScale;
      _lastScale = d.scale;
      final newZoom = (_zoom * scaleDelta).clamp(0.25, 40.0);
      final sf = newZoom / _zoom;
      final panDelta = _lastFocalPoint != null ? focal - _lastFocalPoint! : Offset.zero;
      setState(() {
        _pan = focal + (_pan - focal) * sf + panDelta;
        _zoom = newZoom;
      });
    } else if (_stripState == _StripDrawState.drawing) {
      // Single-finger strip drag.
      setState(() => _stripEnd = _toImage(focal));
    } else if (!_showRecropWarning) {
      // Single-finger crop drag (only if not blocked by recrop warning).
      setState(() => _cropEnd = _toImage(focal));
    }

    _lastFocalPoint = focal;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_stripState == _StripDrawState.drawing &&
        _stripStart != null &&
        _stripEnd != null) {
      final r = Rect.fromPoints(_stripStart!, _stripEnd!);
      if (r.width >= 1 && r.height >= 1) {
        final horizontal = r.width >= r.height;
        final detected =
            _image != null ? SpriteImporter.detectPaletteStrip(_image!, r, horizontal) : <Color>[];
        setState(() {
          _confirmedStrips.add(r);
          _detectedStripColours.add(detected);
          _stripState = _StripDrawState.idle;
          _stripStart = null;
          _stripEnd = null;
        });
      } else {
        setState(() {
          _stripState = _StripDrawState.idle;
          _stripStart = null;
          _stripEnd = null;
        });
      }
    } else if (_pointerCount == 0 && _hasCrop) {
      // Crop drag just ended — refresh the preview.
      setState(() => _refreshCropPreview());
    }
    _lastScale = 1.0;
    _lastFocalPoint = null;
  }

  // ── Import ───────────────────────────────────────────────────────────────────

  Rect? get _selectedRegion {
    if (_image == null) return null;
    if (_cropStart == null || _cropEnd == null) return null;
    final r = Rect.fromPoints(_cropStart!, _cropEnd!);
    if (r.width < 1 || r.height < 1) return null;
    return r;
  }

  Future<void> _addToSnippets() async {
    final region = _selectedRegion;
    if (region == null || _image == null) return;

    setState(() => _importing = true);
    try {
      // Build palette strip colour lists from confirmed strips.
      final List<List<Color>> paletteStripColours = [];
      for (final stripRect in _confirmedStrips) {
        final horizontal = stripRect.width >= stripRect.height;
        final colours =
            SpriteImporter.detectPaletteStrip(_image!, stripRect, horizontal);
        if (colours.isNotEmpty) paletteStripColours.add(colours);
      }

      final name = _nameCtrl.text.trim().isEmpty
          ? 'Sprite'
          : _nameCtrl.text.trim();

      final snippet = await SpriteImporter.importRegionWithPalettes(
        image: _image!,
        region: region,
        name: name,
        mergeThreshold: _mergeThreshold,
        paletteStrips: paletteStripColours,
      );

      if (snippet.stitches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No stitches — region may be fully transparent')),
          );
        }
        return;
      }

      ref.read(editorProvider.notifier).addSnippet(snippet);

      setState(() {
        _addedCount++;
        _nameCtrl.text = 'Sprite ${_addedCount + 1}';
        _cropStart = null;
        _cropEnd = null;
        _cropPreviewBytes = null;
        _confirmedStrips.clear();
        _detectedStripColours.clear();
        _stripState = _StripDrawState.idle;
        _stripStart = null;
        _stripEnd = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('"${name.isEmpty ? 'Snippet' : name}" added to snippets')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null && _image != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprite Sheet'),
        actions: [
          if (hasImage)
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Change image'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_addedCount > 0),
            child: const Text('Close'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: hasImage ? _buildImageLayout() : _buildEmptyState(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_on_outlined,
              size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          Text(
            'Open a sprite sheet image to import sprites as snippets.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Open image'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageLayout() {
    return Column(
      children: [
        if (_showRecropWarning) _buildRecropWarning(),
        if (_stripState == _StripDrawState.drawing) _buildStripCancelBanner(),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildCanvas()),
              _buildControlsPanel(),
            ],
          ),
        ),
        if (_hasCrop || _confirmedStrips.isNotEmpty) _buildPreviewPanel(),
      ],
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      _containerSize = size;

      // Compute fit-transform for this frame (used until first interaction).
      double zoom = _zoom;
      Offset pan = _pan;
      if (_autoFit && _image != null) {
        zoom = min(size.width / _image!.width, size.height / _image!.height);
        pan = Offset(
          (size.width - _image!.width * zoom) / 2,
          (size.height - _image!.height * zoom) / 2,
        );
      }

      final imgW = _image!.width.toDouble();
      final imgH = _image!.height.toDouble();
      final cropRect = (_cropStart != null && _cropEnd != null)
          ? Rect.fromPoints(_cropStart!, _cropEnd!)
          : null;

      return Listener(
        onPointerDown: (_) => _pointerCount++,
        onPointerUp: (_) {
          if (_pointerCount > 0) _pointerCount--;
        },
        onPointerCancel: (_) {
          if (_pointerCount > 0) _pointerCount--;
        },
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: Stack(
              children: [
                // Checkerboard background (shows transparency).
                CustomPaint(
                  size: size,
                  painter: _CheckerPainter(),
                ),
                // Image positioned and scaled by the current transform.
                Positioned(
                  left: pan.dx,
                  top: pan.dy,
                  width: imgW * zoom,
                  height: imgH * zoom,
                  child: Image.memory(
                    _imageBytes!,
                    fit: BoxFit.fill,
                    filterQuality: zoom >= 3
                        ? FilterQuality.none
                        : FilterQuality.medium,
                  ),
                ),
                // Overlay: crop + strip rects.
                CustomPaint(
                  size: size,
                  painter: SpriteSheetPainter(
                    imageSize: Size(imgW, imgH),
                    zoom: zoom,
                    pan: pan,
                    cropRect: (_cropStart != null && _cropEnd != null)
                        ? Rect.fromPoints(_cropStart!, _cropEnd!)
                        : null,
                    paletteStrips: _confirmedStrips,
                    stripDraftRect: (_stripState != _StripDrawState.idle &&
                            _stripStart != null &&
                            _stripEnd != null)
                        ? Rect.fromPoints(_stripStart!, _stripEnd!)
                        : null,
                    isDrawingStrip: _stripState == _StripDrawState.drawing,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildControlsPanel() {
    final theme = Theme.of(context);
    final hasStrips = _confirmedStrips.isNotEmpty;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Palette section ──────────────────────────────────────────────
          Text('Palette', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          if (!hasStrips)
            Text(
              'Auto (detected from crop)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _confirmedStrips.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_outlined, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('Palette ${i + 1}',
                              style: theme.textTheme.bodySmall),
                        ),
                        // Only allow removal if it's not the only strip
                        // blocking others, or always allow individual removal.
                        if (_confirmedStrips.length > 1 || i > 0)
                          InkWell(
                            onTap: () => setState(() {
                              _confirmedStrips.removeAt(i);
                              if (i < _detectedStripColours.length) {
                                _detectedStripColours.removeAt(i);
                              }
                            }),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),

          const SizedBox(height: 8),

          // ── "Add palette strip" button ────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _hasCrop
                ? () => setState(() => _stripState = _StripDrawState.drawing)
                : null,
            icon: const Icon(Icons.add, size: 16),
            label: Text(hasStrips
                ? 'Draw another palette strip'
                : 'Add palette strip'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),

          const Divider(height: 20),

          // ── Simplify palette slider ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text('Simplify palette:',
                    style: theme.textTheme.bodySmall),
              ),
              Tooltip(
                message:
                    'Merges rare DMC colours into their nearest match.\n'
                    'Any colour used in fewer than N pixels is replaced\n'
                    'by the closest colour that meets the threshold.\n'
                    'Reduces thread count for more stitchable results.',
                child: Icon(Icons.info_outline,
                    size: 14, color: theme.disabledColor),
              ),
            ],
          ),
          Slider(
            value: _mergeThreshold.toDouble(),
            min: 0,
            max: 20,
            divisions: 20,
            onChanged: (v) => setState(() => _mergeThreshold = v.round()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _mergeThreshold == 0 ? 'Off' : '< $_mergeThreshold px',
              style: theme.textTheme.bodySmall,
            ),
          ),

          const Divider(height: 20),

          // ── Snippet name ──────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Snippet name',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),

          const SizedBox(height: 12),

          // ── Add to Snippets ────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (_hasCrop && !_importing) ? _addToSnippets : null,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Add to Snippets'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecropWarning() {
    return MaterialBanner(
      content: const Text(
          'Moving the crop will clear your palette selections.'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _showRecropWarning = false;
            _confirmedStrips.clear();
            _detectedStripColours.clear();
            // Crop drag can now proceed freely.
          }),
          child: const Text('Proceed'),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _showRecropWarning = false),
        ),
      ],
    );
  }

  Widget _buildStripCancelBanner() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.palette_outlined, size: 16),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Draw a region around the palette strip')),
          TextButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel palette selection'),
            onPressed: () => setState(() {
              _stripState = _StripDrawState.idle;
              _stripStart = null;
              _stripEnd = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (!_hasCrop && _confirmedStrips.isEmpty) return const SizedBox.shrink();

    final tabCount = 1 + _confirmedStrips.length;
    final tabs = <Widget>[
      const Tab(text: 'Default'),
      for (int i = 0; i < _confirmedStrips.length; i++)
        Tab(text: 'Palette ${i + 1}'),
    ];

    return Container(
      height: 140,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: DefaultTabController(
        length: tabCount,
        child: Column(
          children: [
            TabBar(
              tabs: tabs,
              isScrollable: true,
              labelStyle: const TextStyle(fontSize: 12),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildDefaultPreviewTab(),
                  for (int i = 0; i < _confirmedStrips.length; i++)
                    _buildPaletteStripTab(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultPreviewTab() {
    if (_cropPreviewBytes == null) {
      return const Center(
        child: Text('Draw a crop region to preview',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Center(
        child: Image.memory(
          _cropPreviewBytes!,
          filterQuality: FilterQuality.none,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildPaletteStripTab(int index) {
    final colours = index < _detectedStripColours.length
        ? _detectedStripColours[index]
        : <Color>[];

    if (colours.isEmpty) {
      return const Center(
        child: Text('No colours detected in strip',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${colours.length} colour${colours.length == 1 ? '' : 's'} detected:',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final c in colours)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Checkerboard background ───────────────────────────────────────────────────

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tileSize = 8.0;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y * tileSize < size.height; y++) {
      for (var x = 0; x * tileSize < size.width; x++) {
        paint.color =
            (x + y).isEven ? const Color(0xFFCCCCCC) : const Color(0xFF999999);
        canvas.drawRect(
          Rect.fromLTWH(
              x * tileSize, y * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter _) => false;
}
