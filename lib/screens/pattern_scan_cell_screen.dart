import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pattern_scan_crop_screen.dart';

/// Cell-size measurement result for one cropped stitch grid.
class GridCellResult {
  final GridCropResult crop;

  /// Cell width in image pixels (300 DPI source space).
  final double cellW;

  /// Cell height in image pixels (300 DPI source space).
  final double cellH;

  /// Number of full columns: floor(crop.cropRect.width / cellW).
  final int columns;

  /// Number of full rows: floor(crop.cropRect.height / cellH).
  final int rows;

  /// Grid phase offset within the crop (image pixels).
  /// The first grid column/row starts at this distance from the crop's top-left.
  /// Derived from where the user placed the marked cell: `cell.left % cellW`.
  final double cellOffsetX;
  final double cellOffsetY;

  /// If true, the call site should apply this cell size to all remaining pages
  /// instead of prompting for each one individually.
  final bool applyToAll;

  const GridCellResult({
    required this.crop,
    required this.cellW,
    required this.cellH,
    required this.columns,
    required this.rows,
    this.cellOffsetX = 0,
    this.cellOffsetY = 0,
    this.applyToAll = false,
  });

  /// Return a copy with [applyToAll] set.
  GridCellResult copyWithApplyToAll(bool v) => GridCellResult(
        crop: crop,
        cellW: cellW,
        cellH: cellH,
        columns: columns,
        rows: rows,
        cellOffsetX: cellOffsetX,
        cellOffsetY: cellOffsetY,
        applyToAll: v,
      );

  /// Return a copy adapted to a different crop (recomputes cols/rows).
  GridCellResult withCrop(GridCropResult newCrop) => GridCellResult(
        crop: newCrop,
        cellW: cellW,
        cellH: cellH,
        cellOffsetX: cellOffsetX,
        cellOffsetY: cellOffsetY,
        columns: ((newCrop.cropRect.width - cellOffsetX) / cellW).round().clamp(1, 9999),
        rows: ((newCrop.cropRect.height - cellOffsetY) / cellH).round().clamp(1, 9999),
        applyToAll: false,
      );
}

/// Full-screen UI for measuring exactly one grid cell within a cropped stitch
/// grid page.
///
/// Shows the cropped region of the rasterised page and lets the user drag to
/// mark one cell. As soon as the drag defines a valid rectangle the entire grid
/// is overlaid so the user can verify the division looks correct.
///
/// Pops with a [GridCellResult] when confirmed, or null if cancelled.
class PatternScanCellScreen extends StatefulWidget {
  final GridCropResult crop;

  /// Show the "use same cell for remaining pages" option.
  final bool showCopyOption;

  final int pageIndex;
  final int pageCount;

  /// Pre-detected cell rect in crop-relative image pixels.
  /// When provided the editor opens with this cell already drawn.
  final Rect? initialCellRect;

  const PatternScanCellScreen({
    super.key,
    required this.crop,
    this.showCopyOption = false,
    this.pageIndex = 0,
    this.pageCount = 1,
    this.initialCellRect,
  });

  static Future<GridCellResult?> show(
    BuildContext context, {
    required GridCropResult crop,
    bool showCopyOption = false,
    int pageIndex = 0,
    int pageCount = 1,
    Rect? initialCellRect,
  }) =>
      Navigator.of(context).push<GridCellResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PatternScanCellScreen(
            crop: crop,
            showCopyOption: showCopyOption,
            pageIndex: pageIndex,
            pageCount: pageCount,
            initialCellRect: initialCellRect,
          ),
        ),
      );

  @override
  State<PatternScanCellScreen> createState() => _PatternScanCellScreenState();
}

class _PatternScanCellScreenState extends State<PatternScanCellScreen> {
  ui.Image? _image;
  bool _applyToAll = false;

  // Cell rectangle in crop-relative image pixels.
  Rect? _cell;

  @override
  void initState() {
    super.initState();
    _cell = widget.initialCellRect;
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.crop.pageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
    codec.dispose();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect? get _cellRect => (_cell != null && _cell!.width >= 2 && _cell!.height >= 2)
      ? _cell
      : null;

  GridCellResult? _buildResult() {
    final cell = _cellRect;
    if (cell == null) return null;
    // Grid phase: distance from crop origin to first grid line.
    final offsetX = cell.left % cell.width;
    final offsetY = cell.top % cell.height;
    final cols = ((widget.crop.cropRect.width - offsetX) / cell.width).round();
    final rows = ((widget.crop.cropRect.height - offsetY) / cell.height).round();
    if (cols < 1 || rows < 1) return null;
    return GridCellResult(
      crop: widget.crop,
      cellW: cell.width,
      cellH: cell.height,
      cellOffsetX: offsetX,
      cellOffsetY: offsetY,
      columns: cols,
      rows: rows,
      applyToAll: _applyToAll,
    );
  }

  void _confirm() {
    final result = _buildResult();
    if (result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _buildResult();
    final theme = Theme.of(context);
    final pageLabel = widget.pageCount > 1
        ? ' — page ${widget.pageIndex + 1} of ${widget.pageCount}'
        : '';

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text('Mark one grid cell$pageLabel'),
        actions: [
          TextButton(
            onPressed: result != null ? _confirm : null,
            child: Text(
              'Done',
              style: TextStyle(
                color: result != null ? Colors.white : Colors.white38,
              ),
            ),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Drag to mark exactly one stitch cell. '
                    'The full grid will be computed from its size.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (widget.initialCellRect != null) ...[
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

          // Cell editor + stats bar overlay.
          // Stats bar is Positioned so it never changes the editor's height.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _image == null
                      ? const Center(child: CircularProgressIndicator())
                      : _CellEditor(
                          image: _image!,
                          cropRect: widget.crop.cropRect,
                          cellRect: _cellRect,
                          onCellChanged: (r) => setState(() => _cell = r),
                        ),
                ),
                if (result != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _StatsBar(
                      result: result,
                      showCopyOption: widget.showCopyOption,
                      applyToAll: _applyToAll,
                      onApplyToAllChanged: (v) =>
                          setState(() => _applyToAll = v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cell handle enum ──────────────────────────────────────────────────────────

enum _CellHandle { topLeft, topRight, bottomLeft, bottomRight }

// ── Cell editor ───────────────────────────────────────────────────────────────

class _CellEditor extends StatefulWidget {
  final ui.Image image;
  final Rect cropRect;

  /// Marked cell in crop-relative image pixels; null = not yet set.
  final Rect? cellRect;

  /// Called whenever the cell changes (draw or resize). Null = cleared.
  final void Function(Rect?) onCellChanged;

  const _CellEditor({
    required this.image,
    required this.cropRect,
    required this.cellRect,
    required this.onCellChanged,
  });

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  final _tc = TransformationController();

  // Layout — updated from LayoutBuilder before any gesture fires.
  double _scale = 1.0;
  double _ox = 0.0;
  double _oy = 0.0;

  // Used only during an active draw gesture.
  Offset? _drawStart;

  static const double _minPx = 2.0;
  static const double _hitSize = 44.0;
  static const double _knobSize = 2.0;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _updateLayout(BoxConstraints c) {
    final cropW = widget.cropRect.width;
    final cropH = widget.cropRect.height;
    _scale = min(c.maxWidth / cropW, c.maxHeight / cropH);
    _ox = (c.maxWidth - cropW * _scale) / 2;
    _oy = (c.maxHeight - cropH * _scale) / 2;
  }

  Offset _toCrop(Offset w) => Offset(
        ((w.dx - _ox) / _scale).clamp(0.0, widget.cropRect.width),
        ((w.dy - _oy) / _scale).clamp(0.0, widget.cropRect.height),
      );

  void _dragHandle(_CellHandle handle, Offset delta) {
    final cell = widget.cellRect;
    if (cell == null) return;
    final dx = delta.dx / _scale;
    final dy = delta.dy / _scale;
    final cw = widget.cropRect.width;
    final ch = widget.cropRect.height;
    double l = cell.left, t = cell.top, r = cell.right, b = cell.bottom;
    switch (handle) {
      case _CellHandle.topLeft:
        l = (l + dx).clamp(0.0, r - _minPx);
        t = (t + dy).clamp(0.0, b - _minPx);
      case _CellHandle.topRight:
        r = (r + dx).clamp(l + _minPx, cw);
        t = (t + dy).clamp(0.0, b - _minPx);
      case _CellHandle.bottomLeft:
        l = (l + dx).clamp(0.0, r - _minPx);
        b = (b + dy).clamp(t + _minPx, ch);
      case _CellHandle.bottomRight:
        r = (r + dx).clamp(l + _minPx, cw);
        b = (b + dy).clamp(t + _minPx, ch);
    }
    widget.onCellChanged(Rect.fromLTRB(l, t, r, b));
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cellRect;

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _tc,
          panEnabled: false,
          scaleEnabled: true,
          minScale: 1.0,
          maxScale: 10.0,
          child: LayoutBuilder(builder: (_, constraints) {
            _updateLayout(constraints);

            // Corner handle positions in widget (pre-transform) space.
            final handleDefs = cell == null
                ? <(_CellHandle, double, double)>[]
                : [
                    (_CellHandle.topLeft,     _ox + cell.left  * _scale, _oy + cell.top    * _scale),
                    (_CellHandle.topRight,    _ox + cell.right * _scale, _oy + cell.top    * _scale),
                    (_CellHandle.bottomLeft,  _ox + cell.left  * _scale, _oy + cell.bottom * _scale),
                    (_CellHandle.bottomRight, _ox + cell.right * _scale, _oy + cell.bottom * _scale),
                  ];

            return Stack(
              children: [
                // Background — draw new cell by dragging.
                MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) {
                      _drawStart = _toCrop(d.localPosition);
                      widget.onCellChanged(
                          Rect.fromPoints(_drawStart!, _drawStart!));
                    },
                    onPanUpdate: (d) {
                      if (_drawStart == null) return;
                      widget.onCellChanged(
                          Rect.fromPoints(_drawStart!, _toCrop(d.localPosition)));
                    },
                    onPanEnd: (_) => _drawStart = null,
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _CellPainter(
                        image: widget.image,
                        cropRect: widget.cropRect,
                        scale: _scale,
                        ox: _ox,
                        oy: _oy,
                        cellRect: cell,
                        cellOffsetX: cell == null ? 0 : cell.left % cell.width,
                        cellOffsetY: cell == null ? 0 : cell.top % cell.height,
                      ),
                    ),
                  ),
                ),

                // Corner resize handles — rendered above background drag area.
                for (final (handle, wx, wy) in handleDefs)
                  Positioned(
                    left: wx - _hitSize / 2,
                    top: wy - _hitSize / 2,
                    width: _hitSize,
                    height: _hitSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // onPanStart is required so this recognizer claims the
                      // gesture arena before the background draw detector does.
                      onPanStart: (_) => _drawStart = null,
                      onPanUpdate: (d) => _dragHandle(handle, d.delta),
                      child: Center(
                        child: Container(
                          width: _knobSize,
                          height: _knobSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.black38),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, color: Color(0x44000000)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),

        // Reset zoom — outside the transform so it stays in screen space.
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
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
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

// ── Cell painter ──────────────────────────────────────────────────────────────

class _CellPainter extends CustomPainter {
  final ui.Image image;

  /// Source region of the page image to display.
  final Rect cropRect;

  final double scale;
  final double ox; // x-offset of crop's left edge in widget space
  final double oy; // y-offset of crop's top edge in widget space

  /// Selected cell in *crop-relative* image pixels.
  final Rect? cellRect;

  /// Grid phase offsets (in crop-relative image pixels) — passed through from GridCellResult.
  final double cellOffsetX;
  final double cellOffsetY;

  const _CellPainter({
    required this.image,
    required this.cropRect,
    required this.scale,
    required this.ox,
    required this.oy,
    required this.cellRect,
    this.cellOffsetX = 0,
    this.cellOffsetY = 0,
  });

  /// Map a rect in crop-relative image pixels → widget space.
  Rect _toWidget(Rect r) => Rect.fromLTRB(
        ox + r.left * scale,
        oy + r.top * scale,
        ox + r.right * scale,
        oy + r.bottom * scale,
      );

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the crop region of the full page image.
    final destRect = _toWidget(
      Rect.fromLTWH(0, 0, cropRect.width, cropRect.height),
    );
    canvas.drawImageRect(image, cropRect, destRect, Paint());

    if (cellRect == null) return;

    final cellW = cellRect!.width;
    final cellH = cellRect!.height;
    // Use the same offset/cols/rows logic as GridCellResult._buildResult.
    final offsetX = cellOffsetX;
    final offsetY = cellOffsetY;
    final cols = ((cropRect.width - offsetX) / cellW).round();
    final rows = ((cropRect.height - offsetY) / cellH).round();

    // 2. Ghost grid overlay — aligned to the marked cell's grid phase.
    final gridPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final gridLeft = ox + offsetX * scale;
    final gridTop = oy + offsetY * scale;

    for (var r = 0; r <= rows; r++) {
      final y = gridTop + r * cellH * scale;
      canvas.drawLine(
        Offset(gridLeft, y),
        Offset(gridLeft + cols * cellW * scale, y),
        gridPaint,
      );
    }
    for (var c = 0; c <= cols; c++) {
      final x = gridLeft + c * cellW * scale;
      canvas.drawLine(
        Offset(x, gridTop),
        Offset(x, gridTop + rows * cellH * scale),
        gridPaint,
      );
    }

    // 3. Highlight selected cell with fill + bright border.
    final cellWidgetRect = _toWidget(cellRect!);
    canvas.drawRect(
      cellWidgetRect,
      Paint()..color = Colors.cyan.withValues(alpha: 0.15),
    );
    canvas.drawRect(
      cellWidgetRect,
      Paint()
        ..color = Colors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_CellPainter old) =>
      old.cellRect != cellRect ||
      old.cropRect != cropRect ||
      old.scale != scale ||
      old.ox != ox ||
      old.oy != oy ||
      old.cellOffsetX != cellOffsetX ||
      old.cellOffsetY != cellOffsetY;
}

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final GridCellResult result;
  final bool showCopyOption;
  final bool applyToAll;
  final void Function(bool) onApplyToAllChanged;

  const _StatsBar({
    required this.result,
    required this.showCopyOption,
    required this.applyToAll,
    required this.onApplyToAllChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grid dimension chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip('${result.columns} cols'),
              _Chip('${result.rows} rows'),
              _Chip(
                'cell ${result.cellW.toStringAsFixed(1)}'
                ' × ${result.cellH.toStringAsFixed(1)} px',
              ),
            ],
          ),

          // Apply-to-all option (multi-page only)
          if (showCopyOption) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: applyToAll,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) =>
                        onApplyToAllChanged(v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Use same cell size for remaining pages',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.cyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.cyan,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
