import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/gif_renderer.dart';
import '../services/stitch_planner.dart';
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
    _aida = planStitchingV2(
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

  Future<void> _pickStart() async {
    final cell = await showDialog<(int, int)?>(
      context: context,
      builder: (_) => _StartCellPickerDialog(
        cols: widget.cols,
        rows: widget.rows,
        activeCells: widget.cells.toSet(),
        currentStart: _startCell,
      ),
    );
    // null means cancelled (dialog dismissed without a choice).
    if (cell == null || !mounted) return;
    _pause();
    setState(() {
      _startCell = cell;
      _replan();
    });
  }

  void _clearStart() {
    _pause();
    setState(() {
      _startCell = null;
      _replan();
    });
  }

  Future<void> _exportGif() async {
    setState(() => _exporting = true);
    try {
      final colorMap = singleThreadColorMap(widget.threadColor.toARGB32());

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GIF saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
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
                    child: Text(
                      '${widget.title} — ${widget.threadName}',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
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
              child: CustomPaint(
                painter: StitchDemoPainter(
                  aida: _aida,
                  currentSubStep: _subStep,
                  aidaColor: widget.aidaColor,
                ),
                child: const SizedBox.expand(),
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
                        icon: const Icon(Icons.edit_location_alt, size: 14),
                        label: const Text('Set start'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _pickStart,
                      ),
                      if (_startCell != null)
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

// ── Start cell picker ─────────────────────────────────────────────────────────

/// Dialog that lets the user tap any active cell to set the stitching start.
///
/// Returns the chosen `(x, y)` cell when the user confirms, or `null` when
/// they cancel.
class _StartCellPickerDialog extends StatefulWidget {
  final int cols;
  final int rows;
  final Set<(int, int)> activeCells;
  final (int, int)? currentStart;

  const _StartCellPickerDialog({
    required this.cols,
    required this.rows,
    required this.activeCells,
    this.currentStart,
  });

  @override
  State<_StartCellPickerDialog> createState() => _StartCellPickerDialogState();
}

class _StartCellPickerDialogState extends State<_StartCellPickerDialog> {
  (int, int)? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentStart;
  }

  double get _cellSize {
    const maxCanvas = 420.0;
    return (maxCanvas / max(widget.cols, widget.rows)).clamp(10.0, 40.0);
  }

  (int, int)? _cellAt(Offset pos, double cellSize) {
    final x = (pos.dx / cellSize).floor();
    final y = (pos.dy / cellSize).floor();
    if (x < 0 || x >= widget.cols || y < 0 || y >= widget.rows) return null;
    final cell = (x, y);
    return widget.activeCells.contains(cell) ? cell : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cellSize = _cellSize;
    final canvasW = cellSize * widget.cols;
    final canvasH = cellSize * widget.rows;

    return AlertDialog(
      title: const Text('Set start position'),
      content: SizedBox(
        width: min(canvasW + 32, 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tap any filled cell to set where stitching begins.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: GestureDetector(
                      onTapDown: (d) {
                        final cell = _cellAt(d.localPosition, cellSize);
                        if (cell != null) setState(() => _selected = cell);
                      },
                      child: CustomPaint(
                        size: Size(canvasW, canvasH),
                        painter: _CellPickerPainter(
                          cols: widget.cols,
                          rows: widget.rows,
                          activeCells: widget.activeCells,
                          selected: _selected,
                          cellSize: cellSize,
                          activeColor: cs.primaryContainer,
                          selectedColor: cs.primary,
                          gridColor: cs.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selected != null
                  ? 'Start: (${_selected!.$1}, ${_selected!.$2})'
                  : 'No cell selected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _selected != null ? cs.primary : cs.onSurfaceVariant,
                fontWeight:
                    _selected != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected != null
              ? () => Navigator.of(context).pop(_selected)
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _CellPickerPainter extends CustomPainter {
  final int cols;
  final int rows;
  final Set<(int, int)> activeCells;
  final (int, int)? selected;
  final double cellSize;
  final Color activeColor;
  final Color selectedColor;
  final Color gridColor;

  const _CellPickerPainter({
    required this.cols,
    required this.rows,
    required this.activeCells,
    required this.selected,
    required this.cellSize,
    required this.activeColor,
    required this.selectedColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final activePaint = Paint()..color = activeColor;
    final selectedPaint = Paint()..color = selectedColor;

    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final rect = Rect.fromLTWH(
            x * cellSize, y * cellSize, cellSize, cellSize);
        final cell = (x, y);
        if (selected == cell) {
          canvas.drawRect(rect, selectedPaint);
        } else if (activeCells.contains(cell)) {
          canvas.drawRect(rect, activePaint);
        }
        canvas.drawRect(rect, gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_CellPickerPainter old) =>
      old.selected != selected || old.activeCells != activeCells;
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
