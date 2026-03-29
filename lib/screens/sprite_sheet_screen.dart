import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../providers/editor/editor_provider.dart';
import '../services/sprite_importer.dart';
import '../utils/snackbars.dart';
import '../widgets/sprite_sheet_painter.dart';

// ── Corner handle types ───────────────────────────────────────────────────────

enum _Corner { tl, tr, bl, br }

sealed class _CornerHit {
  final _Corner corner;
  const _CornerHit(this.corner);
}

class _CropCorner extends _CornerHit {
  const _CropCorner(super.corner);
}

class _StripCorner extends _CornerHit {
  final int stripIndex;
  const _StripCorner(this.stripIndex, super.corner);
}

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
  // Trackpad pinch-to-zoom (macOS PointerPanZoom events)
  double _trackpadStartZoom = 1.0;
  Offset _trackpadStartPan = Offset.zero;
  Offset? _lastFocalPoint;
  // Set to true as soon as two or more fingers are down in the current gesture
  // sequence.  While true, single-finger events pan the view instead of
  // starting crop/strip draws, preventing the residual finger from a pinch from
  // accidentally triggering a new selection.  Resets only when _pointerCount
  // drops to 0 (all fingers lifted), so a fresh single-finger touch works
  // normally.
  bool _hadMultiTouch = false;
  // Deferred crop-draw intent: set in _onScaleStart, consumed or cancelled
  // in _onScaleUpdate once _pointerCount is known (prevents pinch from
  // accidentally starting a crop draw via the first-finger-down event).
  Offset? _pendingCropPos;
  bool _pendingRecrop = false;

  // ── Crop selection ──────────────────────────────────────────────────────────
  Offset? _cropStart; // image coordinates (always normalised to topLeft after draw)
  Offset? _cropEnd;   // image coordinates (always normalised to bottomRight after draw)

  // ── Palette strip drawing ───────────────────────────────────────────────────
  _StripDrawState _stripState = _StripDrawState.idle;
  Offset? _stripStart;
  Offset? _stripEnd;
  final List<Rect> _confirmedStrips = [];
  final List<List<Color>> _detectedStripColours = [];

  // ── Corner handle resizing ───────────────────────────────────────────────────
  _CornerHit? _activeCornerHit;

  // ── Preview ──────────────────────────────────────────────────────────────────
  Uint8List? _cropPreviewBytes;
  final List<Uint8List?> _palettePreviewBytes = [];
  int? _activePaletteIndex;
  bool _showRaw = false;

  // ── Panel width ───────────────────────────────────────────────────────────────
  double _panelWidth = 260.0;

  // ── Other ───────────────────────────────────────────────────────────────────
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
      if (mounted) showError(context, 'Could not decode image');
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
      _clearStrips();
      _addedCount = 0;
      _nameCtrl.text = 'Sprite 1';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Strip helpers ─────────────────────────────────────────────────────────

  /// Clears all confirmed palette strips and their associated preview data.
  void _clearStrips() {
    _confirmedStrips.clear();
    _detectedStripColours.clear();
    _palettePreviewBytes.clear();
    _activePaletteIndex = null;
  }

  void _removeStrip(int i) {
    setState(() {
      _confirmedStrips.removeAt(i);
      if (i < _detectedStripColours.length) _detectedStripColours.removeAt(i);
      if (i < _palettePreviewBytes.length) _palettePreviewBytes.removeAt(i);
      if (_confirmedStrips.isEmpty) {
        _activePaletteIndex = null;
      } else if (_activePaletteIndex != null &&
          _activePaletteIndex! >= _confirmedStrips.length) {
        _activePaletteIndex = _confirmedStrips.length - 1;
      }
    });
  }

  /// Shows a modal warning that proceeding will clear palette strips.
  /// Clears strips if the user confirms; does nothing on cancel.
  Future<void> _confirmRecrop() async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear palette selections?'),
        content: const Text(
            'Modifying the crop region will remove all palette strip selections.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
    if ((proceed ?? false) && mounted) {
      setState(_clearStrips);
    }
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

  /// Convert image coordinates → screen (canvas-local) coordinates.
  Offset _toScreen(Offset imagePos) => imagePos * _zoom + _pan;

  // ── Corner hit-test ──────────────────────────────────────────────────────────

  /// Returns the first corner handle within [hitRadius] screen pixels of [screenPos].
  /// Checks crop corners first, then palette strip corners.
  _CornerHit? _hitTestCorner(Offset screenPos) {
    const hitRadius = 14.0;

    if (_cropStart != null && _cropEnd != null) {
      final crop = Rect.fromPoints(_cropStart!, _cropEnd!);
      final corners = [
        (_toScreen(crop.topLeft), _Corner.tl),
        (_toScreen(crop.topRight), _Corner.tr),
        (_toScreen(crop.bottomLeft), _Corner.bl),
        (_toScreen(crop.bottomRight), _Corner.br),
      ];
      for (final (pos, corner) in corners) {
        if ((pos - screenPos).distance <= hitRadius) {
          return _CropCorner(corner);
        }
      }
    }

    for (int i = 0; i < _confirmedStrips.length; i++) {
      final strip = _confirmedStrips[i];
      final corners = [
        (_toScreen(strip.topLeft), _Corner.tl),
        (_toScreen(strip.topRight), _Corner.tr),
        (_toScreen(strip.bottomLeft), _Corner.bl),
        (_toScreen(strip.bottomRight), _Corner.br),
      ];
      for (final (pos, corner) in corners) {
        if ((pos - screenPos).distance <= hitRadius) {
          return _StripCorner(i, corner);
        }
      }
    }

    return null;
  }

  // ── Preview helpers ───────────────────────────────────────────────────────────

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

  /// Regenerates all palette preview images from current crop + strip colours.
  ///
  /// Palette 0 is matched and rendered using its own colours.
  /// Palette N (N > 0) matches against Palette 0 colours and renders using
  /// Palette N colours (positional slot-based swap).
  void _regeneratePalettePreviews() {
    if (!_hasCrop || _image == null) {
      _palettePreviewBytes.clear();
      return;
    }
    final crop = Rect.fromPoints(_cropStart!, _cropEnd!);
    final baseColours = _detectedStripColours.isNotEmpty
        ? _detectedStripColours[0]
        : <Color>[];
    for (int i = 0; i < _detectedStripColours.length; i++) {
      final colours = _detectedStripColours[i];
      final Uint8List? bytes;
      if (colours.isEmpty || baseColours.isEmpty) {
        bytes = null;
      } else {
        bytes = SpriteImporter.renderCropWithPalette(
          _image!, crop, baseColours,
          outputPalette: i == 0 ? null : colours,
        );
      }
      if (i < _palettePreviewBytes.length) {
        _palettePreviewBytes[i] = bytes;
      } else {
        _palettePreviewBytes.add(bytes);
      }
    }
  }

  /// Refreshes detected colours and preview for strip at [i] after resize.
  void _refreshStripAt(int i) {
    if (_image == null || i >= _confirmedStrips.length) return;
    final strip = _confirmedStrips[i];
    if (strip.width < 1 || strip.height < 1) return;
    final horizontal = strip.width >= strip.height;
    final detected =
        SpriteImporter.detectPaletteStrip(_image!, strip, horizontal);
    setState(() {
      while (_detectedStripColours.length <= i) { _detectedStripColours.add([]); }
      _detectedStripColours[i] = detected;
      while (_palettePreviewBytes.length <= i) { _palettePreviewBytes.add(null); }
      if (detected.isEmpty || !_hasCrop) {
        _palettePreviewBytes[i] = null;
        return;
      }
      final baseColours = _detectedStripColours[0];
      _palettePreviewBytes[i] = SpriteImporter.renderCropWithPalette(
        _image!, Rect.fromPoints(_cropStart!, _cropEnd!), baseColours,
        outputPalette: i == 0 ? null : detected,
      );
    });
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
      if (mounted) showError(context, 'Could not decode image');
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
      _clearStrips();
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

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _ensureFit();
    _trackpadStartZoom = _zoom;
    _trackpadStartPan = _pan;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final newZoom = (_trackpadStartZoom * event.scale).clamp(0.25, 40.0);
    setState(() {
      _pan = event.localPosition -
          (event.localPosition - _trackpadStartPan) *
              (newZoom / _trackpadStartZoom) +
          event.pan;
      _zoom = newZoom;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _ensureFit();
    _lastScale = 1.0;
    _lastFocalPoint = d.localFocalPoint;
    _pendingCropPos = null;
    _pendingRecrop = false;

    if (d.pointerCount >= 2) {
      _hadMultiTouch = true;
      return; // multi-touch: zoom/pan handled in _onScaleUpdate
    }

    if (_hadMultiTouch) {
      // A finger is still on screen from a pinch — just pan, don't draw.
      return;
    }

    // Fresh single-touch: check for corner handle hit first.
    final cornerHit = _hitTestCorner(d.localFocalPoint);
    if (cornerHit != null) {
      // Crop corner drags are blocked while palette strips exist.
      if (cornerHit is _CropCorner && _confirmedStrips.isNotEmpty) {
        _confirmRecrop();
        return;
      }
      setState(() => _activeCornerHit = cornerHit);
      return;
    }

    final imgPos = _toImage(d.localFocalPoint);
    if (_stripState == _StripDrawState.drawing) {
      setState(() {
        _stripStart = imgPos;
        _stripEnd = imgPos;
      });
    } else if (_confirmedStrips.isNotEmpty) {
      // Defer the recrop modal until _onScaleUpdate confirms single-touch.
      _pendingRecrop = true;
    } else {
      // Defer crop start until _onScaleUpdate confirms single-touch.
      _pendingCropPos = imgPos;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final focal = d.localFocalPoint;

    if (d.pointerCount >= 2) {
      // Multi-touch pinch: mark as multi-touch, cancel any draw intent, zoom.
      _hadMultiTouch = true;
      _pendingCropPos = null;
      _pendingRecrop = false;
      final scaleDelta = d.scale / _lastScale;
      _lastScale = d.scale;
      final newZoom = (_zoom * scaleDelta).clamp(0.25, 40.0);
      final sf = newZoom / _zoom;
      final panDelta =
          _lastFocalPoint != null ? focal - _lastFocalPoint! : Offset.zero;
      setState(() {
        _pan = focal + (_pan - focal) * sf + panDelta;
        _zoom = newZoom;
      });
    } else if (_hadMultiTouch) {
      // Residual single finger after a pinch — pan only, never draw.
      final panDelta =
          _lastFocalPoint != null ? focal - _lastFocalPoint! : Offset.zero;
      setState(() => _pan += panDelta);
    } else if (_activeCornerHit != null) {
      _applyCornerDrag(_activeCornerHit!, _toImage(focal));
    } else if (_stripState == _StripDrawState.drawing) {
      setState(() => _stripEnd = _toImage(focal));
    } else {
      // Consume deferred intents now that we know this is a single-finger drag.
      if (_pendingRecrop) {
        _pendingRecrop = false;
        _confirmRecrop();
        return;
      }
      if (_pendingCropPos != null) {
        final start = _pendingCropPos!;
        _pendingCropPos = null;
        setState(() {
          _cropStart = start;
          _cropEnd = _toImage(focal);
        });
        return;
      }
      setState(() => _cropEnd = _toImage(focal));
    }

    _lastFocalPoint = focal;
  }

  void _applyCornerDrag(_CornerHit hit, Offset imgPos) {
    setState(() {
      if (hit is _CropCorner) {
        // _cropStart is always topLeft, _cropEnd is always bottomRight after
        // normalisation on draw end.
        switch (hit.corner) {
          case _Corner.tl:
            _cropStart = imgPos;
          case _Corner.tr:
            _cropStart = Offset(_cropStart!.dx, imgPos.dy);
            _cropEnd = Offset(imgPos.dx, _cropEnd!.dy);
          case _Corner.bl:
            _cropStart = Offset(imgPos.dx, _cropStart!.dy);
            _cropEnd = Offset(_cropEnd!.dx, imgPos.dy);
          case _Corner.br:
            _cropEnd = imgPos;
        }
      } else if (hit is _StripCorner) {
        final s = _confirmedStrips[hit.stripIndex];
        final Offset newTL, newBR;
        switch (hit.corner) {
          case _Corner.tl:
            newTL = imgPos;
            newBR = s.bottomRight;
          case _Corner.tr:
            newTL = Offset(s.left, imgPos.dy);
            newBR = Offset(imgPos.dx, s.bottom);
          case _Corner.bl:
            newTL = Offset(imgPos.dx, s.top);
            newBR = Offset(s.right, imgPos.dy);
          case _Corner.br:
            newTL = s.topLeft;
            newBR = imgPos;
        }
        // fromPoints normalises so we always get a valid rect.
        _confirmedStrips[hit.stripIndex] = Rect.fromPoints(newTL, newBR);
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _pendingCropPos = null;
    _pendingRecrop = false;
    // All fingers are off the screen — safe to reset the multi-touch guard so
    // the next fresh single-finger touch can draw normally.
    if (_pointerCount == 0) _hadMultiTouch = false;
    final cornerHit = _activeCornerHit;

    if (cornerHit != null) {
      setState(() => _activeCornerHit = null);
      if (cornerHit is _CropCorner && _hasCrop) {
        // Normalise so start=topLeft, end=bottomRight for future corner ops.
        final r = Rect.fromPoints(_cropStart!, _cropEnd!);
        setState(() {
          _cropStart = r.topLeft;
          _cropEnd = r.bottomRight;
          _refreshCropPreview();
          _regeneratePalettePreviews();
        });
      } else if (cornerHit is _StripCorner) {
        _refreshStripAt(cornerHit.stripIndex);
      }
      _lastScale = 1.0;
      _lastFocalPoint = null;
      return;
    }

    if (_stripState == _StripDrawState.drawing &&
        _stripStart != null &&
        _stripEnd != null) {
      final r = Rect.fromPoints(_stripStart!, _stripEnd!);
      if (r.width >= 1 && r.height >= 1) {
        final horizontal = r.width >= r.height;
        final detected = _image != null
            ? SpriteImporter.detectPaletteStrip(_image!, r, horizontal)
            : <Color>[];
        final newIndex = _confirmedStrips.length;
        // For the first strip (index 0) match+render with its own colours.
        // For subsequent strips match against strip 0, render with new colours.
        final baseColours = _detectedStripColours.isNotEmpty
            ? _detectedStripColours[0]
            : detected;
        final previewBytes = (detected.isNotEmpty && _hasCrop)
            ? SpriteImporter.renderCropWithPalette(
                _image!, Rect.fromPoints(_cropStart!, _cropEnd!), baseColours,
                outputPalette: _confirmedStrips.isEmpty ? null : detected)
            : null;
        setState(() {
          _confirmedStrips.add(r);
          _detectedStripColours.add(detected);
          _palettePreviewBytes.add(previewBytes);
          _activePaletteIndex = newIndex;
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
    } else if (d.pointerCount == 0 && _hasCrop) {
      // Crop draw ended — normalise and refresh preview.
      final r = Rect.fromPoints(_cropStart!, _cropEnd!);
      setState(() {
        _cropStart = r.topLeft;
        _cropEnd = r.bottomRight;
        _refreshCropPreview();
        _regeneratePalettePreviews();
      });
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
        paletteStrips: paletteStripColours,
      );

      if (snippet.stitches.isEmpty) {
        if (mounted) showError(context, 'No stitches — region may be fully transparent');
        return;
      }

      ref.read(editorProvider.notifier).addSnippet(snippet);

      setState(() {
        _addedCount++;
        _nameCtrl.text = 'Sprite ${_addedCount + 1}';
        _cropStart = null;
        _cropEnd = null;
        _cropPreviewBytes = null;
        _stripState = _StripDrawState.idle;
        _stripStart = null;
        _stripEnd = null;
        _clearStrips();
      });

      if (mounted) showSuccess(context, '"$name" added to snippets');
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
        if (_stripState == _StripDrawState.drawing) _buildStripCancelBanner(),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildCanvas()),
              _buildPanelResizeHandle(),
              _buildControlsPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanelResizeHandle() {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() {
          _panelWidth = (_panelWidth - d.delta.dx).clamp(180.0, 600.0);
        }),
        child: SizedBox(
          width: 5,
          child: ColoredBox(
            color: theme.dividerColor,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      _containerSize = size;

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

      return Listener(
        onPointerDown: (_) => _pointerCount++,
        onPointerUp: (_) {
          if (_pointerCount > 0) _pointerCount--;
        },
        onPointerCancel: (_) {
          if (_pointerCount > 0) _pointerCount--;
        },
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        child: GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: Stack(
              children: [
                CustomPaint(size: size, painter: _CheckerPainter()),
                Positioned(
                  left: pan.dx,
                  top: pan.dy,
                  width: imgW * zoom,
                  height: imgH * zoom,
                  child: Image.memory(
                    _imageBytes!,
                    fit: BoxFit.fill,
                    filterQuality:
                        zoom >= 3 ? FilterQuality.none : FilterQuality.medium,
                  ),
                ),
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
      width: _panelWidth,
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // ── Preview at top ─────────────────────────────────────────────────
          _buildPreviewSection(theme),

          // ── Palette list (scrollable) ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Palette', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  if (!hasStrips)
                    Text(
                      'Auto (detected from crop)',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  else
                    for (int i = 0; i < _confirmedStrips.length; i++)
                      _buildPaletteItem(i, theme),

                  const SizedBox(height: 8),

                  OutlinedButton.icon(
                    onPressed: _hasCrop
                        ? () =>
                            setState(() => _stripState = _StripDrawState.drawing)
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
                ],
              ),
            ),
          ),

          // ── Add to Snippets (fixed at bottom) ─────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
              color: theme.colorScheme.surface,
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 10),
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
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteItem(int i, ThemeData theme) {
    final colours = i < _detectedStripColours.length
        ? _detectedStripColours[i]
        : <Color>[];
    final isActive = _activePaletteIndex == i;

    return GestureDetector(
      onTap: () => setState(() => _activePaletteIndex = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color:
                isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.palette_outlined,
                size: 13,
                color: isActive ? theme.colorScheme.primary : null),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Palette ${i + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive ? theme.colorScheme.primary : null,
                  fontWeight: isActive ? FontWeight.w600 : null,
                ),
              ),
            ),
            // Colour swatches (up to 5).
            ...colours.take(5).map((c) => Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(color: Colors.black12, width: 0.5),
                    borderRadius: BorderRadius.circular(1),
                  ),
                )),
            // Remove button (only when >1 strip).
            if (_confirmedStrips.length > 1) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _removeStrip(i),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(ThemeData theme) {
    // Decide what to display.
    Uint8List? previewBytes;
    if (_showRaw || _activePaletteIndex == null) {
      previewBytes = _cropPreviewBytes;
    } else if (_activePaletteIndex! < _palettePreviewBytes.length) {
      previewBytes = _palettePreviewBytes[_activePaletteIndex!];
    }

    final placeholder = !_hasCrop
        ? 'Draw a crop region to preview'
        : (_activePaletteIndex == null
            ? 'Add a palette strip to see\npalette-filtered preview'
            : 'No preview available');

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Preview',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          SizedBox(
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: previewBytes != null
                  ? Image.memory(
                      previewBytes,
                      filterQuality: FilterQuality.none,
                      fit: BoxFit.contain,
                    )
                  : Center(
                      child: Text(
                        placeholder,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.disabledColor),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: _showRaw,
                  onChanged: (v) => setState(() => _showRaw = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Text('Show raw', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
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
          const Expanded(child: Text('Draw a region around the palette strip')),
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
}

// ── Checkerboard background ───────────────────────────────────────────────────

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tileSize = 8.0;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y * tileSize < size.height; y++) {
      for (var x = 0; x * tileSize < size.width; x++) {
        paint.color = (x + y).isEven
            ? const Color(0xFFCCCCCC)
            : const Color(0xFF999999);
        canvas.drawRect(
          Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter _) => false;
}
