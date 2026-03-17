import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/stitch_plan.dart';
import '../services/gif_renderer.dart';
import '../widgets/stitch_demo_painter.dart';

/// Plays back the step-by-step stitching demonstration for [aida] and lets
/// the user download the animation as a GIF.
class StitchDemoScreen extends StatefulWidget {
  final PlannedAida aida;
  final Color threadColor;
  final String threadName;
  final Color aidaColor;

  const StitchDemoScreen({
    super.key,
    required this.aida,
    required this.threadColor,
    required this.threadName,
    this.aidaColor = const Color(0xFFFAF6F0),
  });

  @override
  State<StitchDemoScreen> createState() => _StitchDemoScreenState();
}

class _StitchDemoScreenState extends State<StitchDemoScreen> {
  // Sub-step counter: 0 = empty canvas,
  // segments.length * kDemoSubFrames = all complete.
  int _subStep = 0;
  bool _playing = false;
  // Default: 6 fps × 6 sub-frames = 1 stitch per second.
  double _fps = kDemoSubFrames.toDouble();
  Timer? _timer;
  bool _exporting = false;

  int get _stitchCount => widget.aida.stitches.length;
  int get _totalSubSteps => _stitchCount * kDemoSubFrames;

  // Human-readable stitch index shown in the UI.
  int get _displayStitch => _subStep ~/ kDemoSubFrames;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  Future<void> _exportGif() async {
    setState(() => _exporting = true);
    try {
      final colorMap = singleThreadColorMap(widget.threadColor.toARGB32());

      final gifBytes = await compute(
        _renderGifIsolate,
        _GifParams(
          aida: widget.aida,
          colorMap: colorMap,
          backgroundArgb: widget.aidaColor.toARGB32(),
        ),
      );

      if (!mounted) return;

      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final suggestedName =
          widget.aida.title.replaceAll(RegExp(r'[^\w\s-]'), '_');
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
                      '${widget.aida.title} — ${widget.threadName}',
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
                  aida: widget.aida,
                  currentSubStep: _subStep,
                  threadColor: widget.threadColor,
                  aidaColor: widget.aidaColor,
                ),
                child: const SizedBox.expand(),
              ),
            ),

            // ── Controls ─────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
