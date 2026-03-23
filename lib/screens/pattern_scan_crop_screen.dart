import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The stitch-grid crop selected by the user for one rasterised PDF page.
///
/// [cropRect] is expressed in image-pixel coordinates (300 DPI source space).
class GridCropResult {
  final Uint8List pageBytes;
  final Rect cropRect;

  const GridCropResult({required this.pageBytes, required this.cropRect});
}

/// Full-screen UI for selecting the stitch-grid crop region on each page.
///
/// Shows each rasterised PDF page one at a time and overlays a draggable
/// rectangle. The user drags the handles to frame only the stitch grid,
/// excluding the colour legend and page margins.
///
/// Pops with a [List<GridCropResult>] (one per page) when confirmed,
/// or null if cancelled.
class PatternScanCropScreen extends StatefulWidget {
  /// Rasterised PNG bytes for each page, in document order.
  final List<Uint8List> pages;

  /// Optional pre-detected crop rects (one per page, null = no detection).
  /// When provided the crop editor opens with the rect already set.
  final List<Rect?> initialCrops;

  const PatternScanCropScreen({
    super.key,
    required this.pages,
    this.initialCrops = const [],
  });

  static Future<List<GridCropResult>?> show(
    BuildContext context, {
    required List<Uint8List> pages,
    List<Rect?> initialCrops = const [],
  }) =>
      Navigator.of(context).push<List<GridCropResult>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PatternScanCropScreen(
            pages: pages,
            initialCrops: initialCrops,
          ),
        ),
      );

  @override
  State<PatternScanCropScreen> createState() => _PatternScanCropScreenState();
}

class _PatternScanCropScreenState extends State<PatternScanCropScreen> {
  int _pageIndex = 0;

  /// Crop rect per page in image pixels; null until the user adjusts (= full image).
  late final List<Rect?> _crops;

  /// Decoded natural dimensions per page.
  late final List<Size?> _imageSizes;

  @override
  void initState() {
    super.initState();
    // Pre-seed crops from auto-detection; pad/truncate to match page count.
    _crops = List.generate(
      widget.pages.length,
      (i) => i < widget.initialCrops.length ? widget.initialCrops[i] : null,
    );
    _imageSizes = List.filled(widget.pages.length, null);
    _decodeSizes();
  }

  Future<void> _decodeSizes() async {
    for (var i = 0; i < widget.pages.length; i++) {
      final codec = await ui.instantiateImageCodec(widget.pages[i]);
      final frame = await codec.getNextFrame();
      final sz = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _imageSizes[i] = sz);
    }
  }

  void _onCropChanged(Rect rect) => _crops[_pageIndex] = rect;

  void _confirm() {
    final results = List.generate(widget.pages.length, (i) {
      // A4 @ 300 DPI fallback when the image hasn't decoded yet.
      final sz = _imageSizes[i] ?? const Size(2480, 3508);
      return GridCropResult(
        pageBytes: widget.pages[i],
        cropRect: _crops[i] ?? Rect.fromLTWH(0, 0, sz.width, sz.height),
      );
    });
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.pages.length;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          pageCount > 1
              ? 'Select stitch grid — page ${_pageIndex + 1} of $pageCount'
              : 'Select stitch grid',
        ),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Instruction banner
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Drag the handles to frame the stitch grid. '
                    'Exclude the colour legend and page margins.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (_pageIndex < widget.initialCrops.length &&
                    widget.initialCrops[_pageIndex] != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Auto-detected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Crop editor
          Expanded(
            child: _imageSizes[_pageIndex] == null
                ? const Center(child: CircularProgressIndicator())
                : _CropEditor(
                    key: ValueKey(_pageIndex),
                    imageBytes: widget.pages[_pageIndex],
                    imageSize: _imageSizes[_pageIndex]!,
                    initialCrop: _crops[_pageIndex],
                    onCropChanged: _onCropChanged,
                  ),
          ),

          // Page navigation (only for multi-page scans)
          if (pageCount > 1)
            _PageNav(
              pageIndex: _pageIndex,
              pageCount: pageCount,
              onPrevious: () => setState(() => _pageIndex--),
              onNext: () => setState(() => _pageIndex++),
              onDone: _confirm,
            ),
        ],
      ),
    );
  }
}

// ── Handle enum ───────────────────────────────────────────────────────────────

enum _Handle {
  topLeft,
  topCenter,
  topRight,
  leftCenter,
  rightCenter,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

// ── Crop editor ───────────────────────────────────────────────────────────────

class _CropEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final Size imageSize;
  final Rect? initialCrop;
  final void Function(Rect) onCropChanged;

  const _CropEditor({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    required this.initialCrop,
    required this.onCropChanged,
  });

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late Rect _crop; // canonical state in image-pixel coordinates

  // Layout-derived values — set each build() from the LayoutBuilder callback
  // before any gesture callback can fire, so always up-to-date.
  double _scale = 1.0;
  double _ox = 0.0; // x-offset: left edge of rendered image in widget space
  double _oy = 0.0; // y-offset: top edge of rendered image in widget space

  final _tc = TransformationController();

  static const double _minPx = 20.0;  // minimum crop (image pixels)
  static const double _hitSize = 44.0; // GestureDetector hit area (widget px)
  static const double _knobSize = 14.0; // visual handle knob (widget px)

  @override
  void initState() {
    super.initState();
    final sz = widget.imageSize;
    _crop = widget.initialCrop ?? Rect.fromLTWH(0, 0, sz.width, sz.height);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _updateLayout(BoxConstraints c) {
    final iw = widget.imageSize.width;
    final ih = widget.imageSize.height;
    _scale = min(c.maxWidth / iw, c.maxHeight / ih);
    _ox = (c.maxWidth - iw * _scale) / 2;
    _oy = (c.maxHeight - ih * _scale) / 2;
  }

  double get _imgW => widget.imageSize.width;
  double get _imgH => widget.imageSize.height;

  void _dragHandle(_Handle handle, Offset delta) {
    final dx = delta.dx / _scale;
    final dy = delta.dy / _scale;
    double l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;

    switch (handle) {
      case _Handle.topLeft:
        l = (l + dx).clamp(0.0, r - _minPx);
        t = (t + dy).clamp(0.0, b - _minPx);
      case _Handle.topCenter:
        t = (t + dy).clamp(0.0, b - _minPx);
      case _Handle.topRight:
        r = (r + dx).clamp(l + _minPx, _imgW);
        t = (t + dy).clamp(0.0, b - _minPx);
      case _Handle.leftCenter:
        l = (l + dx).clamp(0.0, r - _minPx);
      case _Handle.rightCenter:
        r = (r + dx).clamp(l + _minPx, _imgW);
      case _Handle.bottomLeft:
        l = (l + dx).clamp(0.0, r - _minPx);
        b = (b + dy).clamp(t + _minPx, _imgH);
      case _Handle.bottomCenter:
        b = (b + dy).clamp(t + _minPx, _imgH);
      case _Handle.bottomRight:
        r = (r + dx).clamp(l + _minPx, _imgW);
        b = (b + dy).clamp(t + _minPx, _imgH);
    }

    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
    widget.onCropChanged(_crop);
  }

  void _dragInterior(Offset delta) {
    final dx = delta.dx / _scale;
    final dy = delta.dy / _scale;
    final w = _crop.width;
    final h = _crop.height;
    final newL = (_crop.left + dx).clamp(0.0, _imgW - w);
    final newT = (_crop.top + dy).clamp(0.0, _imgH - h);
    setState(() => _crop = Rect.fromLTWH(newL, newT, w, h));
    widget.onCropChanged(_crop);
  }

  MouseCursor _cursorFor(_Handle h) => switch (h) {
        _Handle.topLeft || _Handle.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        _Handle.topRight ||
        _Handle.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
        _Handle.topCenter ||
        _Handle.bottomCenter =>
          SystemMouseCursors.resizeUpDown,
        _Handle.leftCenter ||
        _Handle.rightCenter =>
          SystemMouseCursors.resizeLeftRight,
      };

  static bool _isCorner(_Handle h) =>
      h == _Handle.topLeft ||
      h == _Handle.topRight ||
      h == _Handle.bottomLeft ||
      h == _Handle.bottomRight;

  @override
  Widget build(BuildContext context) {
    // Outer Stack keeps the reset button in screen space (outside the transform).
    return Stack(
      children: [
        // Pinch-to-zoom / two-finger-pan. panEnabled:false lets inner
        // GestureDetectors handle single-finger crop editing uncontested.
        InteractiveViewer(
          transformationController: _tc,
          panEnabled: false,
          scaleEnabled: true,
          minScale: 1.0,
          maxScale: 8.0,
          child: LayoutBuilder(builder: (ctx, constraints) {
            _updateLayout(constraints);

            // Crop bounds in widget (pre-transform) coordinates.
            final cw = Rect.fromLTRB(
              _ox + _crop.left * _scale,
              _oy + _crop.top * _scale,
              _ox + _crop.right * _scale,
              _oy + _crop.bottom * _scale,
            );

            final handleDefs = <(_Handle, double, double)>[
              (_Handle.topLeft, cw.left, cw.top),
              (_Handle.topCenter, cw.center.dx, cw.top),
              (_Handle.topRight, cw.right, cw.top),
              (_Handle.leftCenter, cw.left, cw.center.dy),
              (_Handle.rightCenter, cw.right, cw.center.dy),
              (_Handle.bottomLeft, cw.left, cw.bottom),
              (_Handle.bottomCenter, cw.center.dx, cw.bottom),
              (_Handle.bottomRight, cw.right, cw.bottom),
            ];

            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Page image
                Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),

                // 2. Outside-dim + crop border + rule-of-thirds guide
                IgnorePointer(
                  child: CustomPaint(
                    painter: _CropOverlayPainter(cropRect: cw),
                  ),
                ),

                // 3. Interior drag area (translates the entire crop rect)
                Positioned(
                  left: cw.left,
                  top: cw.top,
                  width: cw.width,
                  height: cw.height,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => _dragInterior(d.delta),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

                // 4. Resize handles — above interior drag area
                for (final (handle, wx, wy) in handleDefs)
                  Positioned(
                    left: wx - _hitSize / 2,
                    top: wy - _hitSize / 2,
                    width: _hitSize,
                    height: _hitSize,
                    child: MouseRegion(
                      cursor: _cursorFor(handle),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => _dragHandle(handle, d.delta),
                        child: Center(
                          child: Container(
                            width: _knobSize,
                            height: _knobSize,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: _isCorner(handle)
                                  ? BorderRadius.circular(3)
                                  : BorderRadius.circular(_knobSize / 2),
                              border: Border.all(color: Colors.black38),
                              boxShadow: const [
                                BoxShadow(blurRadius: 4, color: Color(0x44000000)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),

        // Reset zoom button — outside the transform so it stays at top-right.
        Positioned(
          top: 8,
          right: 8,
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: _tc,
            builder: (context, matrix, child) => AnimatedOpacity(
              opacity: matrix == Matrix4.identity() ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Tooltip(
                message: 'Reset zoom',
                child: IconButton(
                  icon: const Icon(Icons.zoom_out_map),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                  ),
                  onPressed: () => _tc.value = Matrix4.identity(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Overlay painter ───────────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  const _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Darken the area outside the crop rectangle.
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = const Color(0x88000000));

    // Corner L-markers — drawn instead of a full border so the exact crop
    // boundary is unambiguous: the inner tip of the marker is the exact edge.
    const armLen = 22.0;
    final markerPaint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    void drawCorner(Offset pt, double dx, double dy) {
      canvas.drawLine(pt, pt + Offset(dx * armLen, 0), markerPaint);
      canvas.drawLine(pt, pt + Offset(0, dy * armLen), markerPaint);
    }
    drawCorner(cropRect.topLeft,      1,  1);
    drawCorner(cropRect.topRight,    -1,  1);
    drawCorner(cropRect.bottomLeft,   1, -1);
    drawCorner(cropRect.bottomRight, -1, -1);

    // Edge midpoint tick marks — short inward lines at the centre of each edge
    // so the user can see where the midpoint is when the crop is large.
    const tickLen = 8.0;
    canvas.drawLine(
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.top + tickLen),
      markerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.center.dx, cropRect.bottom - tickLen),
      markerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left,  cropRect.center.dy),
      Offset(cropRect.left  + tickLen, cropRect.center.dy),
      markerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.center.dy),
      Offset(cropRect.right - tickLen, cropRect.center.dy),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.cropRect != cropRect;
}

// ── Page navigation bar ───────────────────────────────────────────────────────

class _PageNav extends StatelessWidget {
  final int pageIndex;
  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onDone;

  const _PageNav({
    required this.pageIndex,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70),
              onPressed: pageIndex > 0 ? onPrevious : null,
              child: const Text('Previous'),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${pageIndex + 1} / $pageCount',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            FilledButton(
              onPressed: pageIndex < pageCount - 1 ? onNext : onDone,
              child: Text(
                  pageIndex < pageCount - 1 ? 'Next Page' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}
