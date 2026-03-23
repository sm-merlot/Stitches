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

const _tileSizes = [8, 16, 32, 64];

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen sprite sheet importer.
///
/// The user opens an image, selects tiles or crops regions, and adds them to
/// the current pattern's snippet library via "Add to Snippets".
///
/// Pops with `true` if at least one snippet was added (so the caller can
/// open the snippets panel automatically), or `false` otherwise.
class SpriteSheetScreen extends ConsumerStatefulWidget {
  const SpriteSheetScreen({super.key});

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

  // ── Selection ───────────────────────────────────────────────────────────────
  SpriteMode _mode = SpriteMode.tile;
  int _tileSize = 16;
  int? _selTileX;
  int? _selTileY;
  Offset? _cropStart; // image coordinates
  Offset? _cropEnd;   // image coordinates

  // ── Other ───────────────────────────────────────────────────────────────────
  int _mergeThreshold = 0;
  late final TextEditingController _nameCtrl;
  int _addedCount = 0;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Sprite 1');
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
      _selTileX = null;
      _selTileY = null;
      _cropStart = null;
      _cropEnd = null;
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

    if (_pointerCount == 1 && _mode == SpriteMode.crop) {
      final imgPos = _toImage(d.localFocalPoint);
      setState(() {
        _cropStart = imgPos;
        _cropEnd = imgPos;
      });
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
    } else if (_mode == SpriteMode.crop) {
      // Single-finger crop drag.
      setState(() => _cropEnd = _toImage(focal));
    }

    _lastFocalPoint = focal;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _lastScale = 1.0;
    _lastFocalPoint = null;
  }

  void _onTapDown(TapDownDetails d) {
    if (_mode != SpriteMode.tile) return;
    _ensureFit();
    final img = _toImage(d.localPosition);
    if (_image == null ||
        img.dx < 0 || img.dy < 0 ||
        img.dx >= _image!.width || img.dy >= _image!.height) {
      return;
    }
    setState(() {
      _selTileX = (img.dx / _tileSize).floor();
      _selTileY = (img.dy / _tileSize).floor();
    });
  }

  // ── Import ───────────────────────────────────────────────────────────────────

  Rect? get _selectedRegion {
    if (_image == null) return null;
    if (_mode == SpriteMode.tile) {
      if (_selTileX == null || _selTileY == null) return null;
      return Rect.fromLTWH(
        (_selTileX! * _tileSize).toDouble(),
        (_selTileY! * _tileSize).toDouble(),
        _tileSize.toDouble(),
        _tileSize.toDouble(),
      );
    } else {
      if (_cropStart == null || _cropEnd == null) return null;
      final r = Rect.fromPoints(_cropStart!, _cropEnd!);
      if (r.width < 1 || r.height < 1) return null;
      return r;
    }
  }

  Future<void> _addToSnippets() async {
    final region = _selectedRegion;
    if (region == null || _image == null) return;

    setState(() => _importing = true);
    try {
      final imported = SpriteImporter.importRegion(
        _image!,
        region.left.round(),
        region.top.round(),
        region.width.round(),
        region.height.round(),
        mergeThreshold: _mergeThreshold,
      );

      if (imported.stitches.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No stitches — region may be fully transparent')),
          );
        }
        return;
      }

      final name = _nameCtrl.text.trim();
      final snippet = Snippet.create(
        name: name,
        width: region.width.round().clamp(1, _image!.width),
        height: region.height.round().clamp(1, _image!.height),
        threads: imported.threads,
        stitches: imported.stitches,
      );

      ref.read(editorProvider.notifier).addSnippet(snippet);

      setState(() {
        _addedCount++;
        _nameCtrl.text = 'Sprite ${_addedCount + 1}';
        _selTileX = null;
        _selTileY = null;
        _cropStart = null;
        _cropEnd = null;
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(_addedCount > 0),
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: hasImage ? _buildImageArea() : _buildEmptyState(),
          ),
          if (hasImage)
            _ControlPanel(
              mode: _mode,
              tileSize: _tileSize,
              mergeThreshold: _mergeThreshold,
              nameController: _nameCtrl,
              hasSelection: _selectedRegion != null,
              importing: _importing,
              onModeChanged: (m) => setState(() {
                _mode = m;
                _selTileX = null;
                _selTileY = null;
                _cropStart = null;
                _cropEnd = null;
              }),
              onTileSizeChanged: (s) => setState(() {
                _tileSize = s;
                _selTileX = null;
                _selTileY = null;
              }),
              onMergeThresholdChanged: (v) =>
                  setState(() => _mergeThreshold = v),
              onAdd: _addToSnippets,
              onChangeImage: _pickImage,
            ),
        ],
      ),
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

  Widget _buildImageArea() {
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
          onTapDown: _onTapDown,
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
                // Overlay: grid / selection.
                CustomPaint(
                  size: size,
                  painter: SpriteSheetPainter(
                    imageSize: Size(imgW, imgH),
                    zoom: zoom,
                    pan: pan,
                    mode: _mode,
                    tileSize: _tileSize,
                    selTileX: _selTileX,
                    selTileY: _selTileY,
                    cropRect: cropRect,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
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

// ── Controls panel ─────────────────────────────────────────────────────────────

class _ControlPanel extends StatelessWidget {
  final SpriteMode mode;
  final int tileSize;
  final int mergeThreshold;
  final TextEditingController nameController;
  final bool hasSelection;
  final bool importing;
  final ValueChanged<SpriteMode> onModeChanged;
  final ValueChanged<int> onTileSizeChanged;
  final ValueChanged<int> onMergeThresholdChanged;
  final VoidCallback onAdd;
  final VoidCallback onChangeImage;

  const _ControlPanel({
    required this.mode,
    required this.tileSize,
    required this.mergeThreshold,
    required this.nameController,
    required this.hasSelection,
    required this.importing,
    required this.onModeChanged,
    required this.onTileSizeChanged,
    required this.onMergeThresholdChanged,
    required this.onAdd,
    required this.onChangeImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: mode + tile size + change image.
          Row(
            children: [
              SegmentedButton<SpriteMode>(
                segments: const [
                  ButtonSegment(
                    value: SpriteMode.tile,
                    label: Text('Tile'),
                    icon: Icon(Icons.grid_view_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: SpriteMode.crop,
                    label: Text('Crop'),
                    icon: Icon(Icons.crop, size: 16),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => onModeChanged(s.first),
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 12),
              if (mode == SpriteMode.tile) ...[
                Text('Size:', style: theme.textTheme.bodySmall),
                const SizedBox(width: 6),
                DropdownButton<int>(
                  value: tileSize,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: _tileSizes
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text('${s}px')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onTileSizeChanged(v);
                  },
                ),
                const SizedBox(width: 12),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: onChangeImage,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Change image'),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 2: palette merge slider.
          Row(
            children: [
              Text('Simplify palette:', style: theme.textTheme.bodySmall),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Merges rare DMC colours into their nearest match.\n'
                    'Any colour used in fewer than N pixels is replaced\n'
                    'by the closest colour that meets the threshold.\n'
                    'Reduces thread count for more stitchable results.',
                child: Icon(Icons.info_outline,
                    size: 14, color: theme.disabledColor),
              ),
              Expanded(
                child: Slider(
                  value: mergeThreshold.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (v) => onMergeThresholdChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  mergeThreshold == 0 ? 'Off' : '< $mergeThreshold px',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 3: name + add button.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Snippet name',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: (hasSelection && !importing) ? onAdd : null,
                icon: importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Add to Snippets'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
