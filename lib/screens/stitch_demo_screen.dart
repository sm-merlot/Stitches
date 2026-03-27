import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/gif_renderer.dart';
import '../services/stitch_planner.dart';
import '../services/stitch_renderer.dart' show computeGridBounds, stitchTypeArgb;
import '../utils/snackbars.dart';
import '../widgets/stitch_demo_painter.dart';

/// Plays back the step-by-step stitching demonstration and lets the user
/// choose a starting cell, download the animation as a GIF, etc.
class StitchDemoScreen extends StatefulWidget {
  final String title;
  final int cols;
  final int rows;
  final List<(int, int)> cells;
  final Color threadColor;
  final String threadName;
  final Color aidaColor;

  const StitchDemoScreen({
    super.key,
    required this.title,
    required this.cols,
    required this.rows,
    required this.cells,
    required this.threadColor,
    required this.threadName,
    this.aidaColor = const Color(0xFFFAF6F0),
  });

  @override
  State<StitchDemoScreen> createState() => _StitchDemoScreenState();
}

class _StitchDemoScreenState extends State<StitchDemoScreen> {
  late PlannedAida _aida;
  (int, int)? _startCell;

  // Sub-step counter: 0 = empty canvas,
  // segments.length * kDemoSubFrames = all complete.
  int _subStep = 0;
  bool _playing = false;
  // Default: 6 fps × 6 sub-frames = 1 stitch per second.
  double _fps = kDemoSubFrames.toDouble();
  Timer? _timer;
  bool _exporting = false;
  bool _pickingStart = false;
  Size _canvasSize = Size.zero;

  int get _stitchCount => _aida.stitches.length;
  int get _totalSubSteps => _stitchCount * kDemoSubFrames;

  // Human-readable stitch index shown in the UI.
  int get _displayStitch => _subStep ~/ kDemoSubFrames;

  @override
  void initState() {
    super.initState();
    _replan();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _replan() {
    _aida = planStitching(
      title: widget.title,
      cols: widget.cols,
      rows: widget.rows,
      cells: widget.cells,
      startCell: _startCell,
    );
    _subStep = 0;
  }

  void _play() {
    _timer?.cancel();
    if (_subStep >= _totalSubSteps) _subStep = 0;
    setState(() => _playing = true);
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (_) {
        if (!mounted) return;
        if (_subStep >= _totalSubSteps) {
          _timer?.cancel();
          setState(() {
            _playing = false;
            _subStep = _totalSubSteps;
          });
        } else {
          setState(() => _subStep++);
        }
      },
    );
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  // Step back / forward by one full stitch (kDemoSubFrames sub-steps).
  void _stepBack() {
    _pause();
    setState(() {
      _subStep = (_subStep - kDemoSubFrames).clamp(0, _totalSubSteps);
    });
  }

  void _stepForward() {
    _pause();
    setState(() {
      _subStep = (_subStep + kDemoSubFrames).clamp(0, _totalSubSteps);
    });
  }

  void _reset() {
    _pause();
    setState(() => _subStep = 0);
  }

  void _togglePickingStart() {
    _pause();
    setState(() => _pickingStart = !_pickingStart);
  }

  void _clearStart() {
    _pause();
    setState(() {
      _startCell = null;
      _pickingStart = false;
      _replan();
    });
  }

  /// Converts a tap position on the demo canvas to an active cell coordinate,
  /// replicating the layout math used by [StitchDemoPainter].
  (int, int)? _cellFromOffset(Offset pos) {
    if (_canvasSize == Size.zero) return null;
    final bounds = computeGridBounds(_aida, 1.0);
    if (bounds.width == 0 || bounds.height == 0) return null;
    const paddingFraction = 0.04;
    final padPx = _canvasSize.shortestSide * paddingFraction;
    final availW = _canvasSize.width - padPx * 2;
    final availH = _canvasSize.height - padPx * 2;
    final cellSize = (availW / bounds.width) < (availH / bounds.height)
        ? availW / bounds.width
        : availH / bounds.height;
    final originX =
        (_canvasSize.width - bounds.width * cellSize) / 2 - bounds.left * cellSize;
    final originY =
        (_canvasSize.height - bounds.height * cellSize) / 2 - bounds.top * cellSize;
    final cx = ((pos.dx - originX) / cellSize).round();
    final cy = ((pos.dy - originY) / cellSize).round();
    final cell = (cx, cy);
    return widget.cells.contains(cell) ? cell : null;
  }

  Future<void> _exportGif() async {
    setState(() => _exporting = true);
    try {
      final colorMap = Map<StitchType, int>.from(stitchTypeArgb);

      final gifBytes = await compute(
        _renderGifIsolate,
        _GifParams(
          aida: _aida,
          colorMap: colorMap,
          backgroundArgb: widget.aidaColor.toARGB32(),
        ),
      );

      if (!mounted) return;

      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final suggestedName =
          _aida.title.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final path = await FilePicker.platform.saveFile(
        fileName: isMobile ? '$suggestedName.gif' : suggestedName,
        type: isMobile ? FileType.any : FileType.custom,
        allowedExtensions: isMobile ? null : ['gif'],
      );

      if (path == null) return;
      final finalPath = path.endsWith('.gif') ? path : '$path.gif';
      await File(finalPath).writeAsBytes(gifBytes);

      if (mounted) showSuccess(context, 'GIF saved');
    } catch (e) {
      if (mounted) showError(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 680,
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${widget.title} — ${widget.threadName}',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'BETA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_exporting)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Tooltip(
                      message: 'Download GIF',
                      child: IconButton(
                        icon: const Icon(Icons.download_outlined, size: 20),
                        visualDensity: VisualDensity.compact,
                        onPressed: _exportGif,
                      ),
                    ),
                  Tooltip(
                    message: 'Close',
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),

            // ── Canvas ───────────────────────────────────────────────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _canvasSize = constraints.biggest;
                  return GestureDetector(
                    onTapDown: _pickingStart
                        ? (d) {
                            final cell = _cellFromOffset(d.localPosition);
                            if (cell == null) return;
                            setState(() {
                              _startCell = cell;
                              _pickingStart = false;
                              _replan();
                            });
                          }
                        : null,
                    child: Stack(
                      children: [
                        CustomPaint(
                          painter: StitchDemoPainter(
                            aida: _aida,
                            currentSubStep: _subStep,
                            aidaColor: widget.aidaColor,
                            startCell: _startCell,
                            pickingStart: _pickingStart,
                          ),
                          child: const SizedBox.expand(),
                        ),
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: _StitchLegend(),
                        ),
                        if (_pickingStart)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Tap a cell to set start',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Controls ─────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stitch counter + speed label
                  Row(
                    children: [
                      Text(
                        'Stitch $_displayStitch / $_stitchCount',
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        '${(_fps / kDemoSubFrames).toStringAsFixed(1)} stitches/s',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: _stitchCount == 0 ? 0 : _subStep / _totalSubSteps,
                    minHeight: 2,
                  ),
                  const SizedBox(height: 4),
                  // Playback row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        tooltip: 'Reset',
                        onPressed: _subStep > 0 ? _reset : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous stitch',
                        onPressed: _subStep > 0 ? _stepBack : null,
                      ),
                      FilledButton.icon(
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        label: Text(_playing ? 'Pause' : 'Play'),
                        onPressed: _playing ? _pause : _play,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next stitch',
                        onPressed:
                            _subStep < _totalSubSteps ? _stepForward : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        tooltip: 'Jump to end',
                        onPressed: _subStep < _totalSubSteps
                            ? () {
                                _pause();
                                setState(() => _subStep = _totalSubSteps);
                              }
                            : null,
                      ),
                    ],
                  ),
                  // Speed slider
                  Row(
                    children: [
                      const Icon(Icons.slow_motion_video, size: 16),
                      Expanded(
                        child: Slider(
                          min: kDemoSubFrames.toDouble(),
                          max: kDemoSubFrames.toDouble() * 8,
                          divisions: 7,
                          value: _fps,
                          label:
                              '${(_fps / kDemoSubFrames).round()} stitches/s',
                          onChanged: (v) {
                            setState(() => _fps = v);
                            if (_playing) _play();
                          },
                        ),
                      ),
                      const Icon(Icons.fast_forward, size: 16),
                    ],
                  ),
                  // Start position row
                  Row(
                      children: [
                        Icon(Icons.my_location,
                            size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          _startCell != null
                              ? 'Start: (${_startCell!.$1}, ${_startCell!.$2})'
                              : 'Start: default',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _startCell != null
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: Icon(
                            _pickingStart
                                ? Icons.close
                                : Icons.edit_location_alt,
                            size: 14,
                          ),
                          label: Text(_pickingStart ? 'Cancel' : 'Set start'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _togglePickingStart,
                        ),
                        if (_startCell != null && !_pickingStart)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _clearStart,
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stitch type legend ────────────────────────────────────────────────────────

class _StitchLegend extends StatelessWidget {
  const _StitchLegend();

  static const _entries = [
    (Color(0xFF9B30D0), 'front, pass 1', false, false),
    (Color(0xFF27AE60), 'front, pass 2', false, false),
    (Color(0xFFE6B800), 'back, pass 1',  false, true),
    (Color(0xFFE63030), 'back, pass 2',  false, true),
    (Color(0xFF0074D9), 'back, pass 3',  false, true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _entries
            .map((e) => _LegendRow(color: e.$1, label: e.$2, isBack: e.$3, isDashed: e.$4))
            .toList(),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool isBack;
  final bool isDashed;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.isBack,
    required this.isDashed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 10,
            child: CustomPaint(
              painter: _LineSamplePainter(
                  color: color, isDashed: isDashed),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineSamplePainter extends CustomPainter {
  final Color color;
  final bool isDashed;

  const _LineSamplePainter({required this.color, required this.isDashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    if (!isDashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      var x = 0.0;
      var drawing = true;
      while (x < size.width) {
        final len = (drawing ? 4.0 : 3.0).clamp(0.0, size.width - x);
        if (drawing && len > 0) {
          canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
        }
        x += len;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(_LineSamplePainter old) =>
      old.color != color || old.isDashed != isDashed;
}


// ── Isolate helpers ───────────────────────────────────────────────────────────

class _GifParams {
  final PlannedAida aida;
  final Map<StitchType, int> colorMap;
  final int backgroundArgb;

  const _GifParams({
    required this.aida,
    required this.colorMap,
    required this.backgroundArgb,
  });
}

List<int> _renderGifIsolate(_GifParams p) => renderDemoGif(
      aida: p.aida,
      colorMap: p.colorMap,
      backgroundArgb: p.backgroundArgb,
    );
