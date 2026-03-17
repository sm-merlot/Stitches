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
  int _step = 0;
  bool _playing = false;
  double _fps = 4.0;
  Timer? _timer;
  bool _exporting = false;

  int get _totalSteps => widget.aida.stitches.length + 1; // 0 = empty canvas

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    if (_step >= _totalSteps - 1) _step = 0;
    setState(() => _playing = true);
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (_) {
        if (!mounted) return;
        if (_step >= _totalSteps - 1) {
          _timer?.cancel();
          setState(() {
            _playing = false;
            _step = _totalSteps - 1;
          });
        } else {
          setState(() => _step++);
        }
      },
    );
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  void _stepBack() {
    _pause();
    setState(() => _step = (_step - 1).clamp(0, _totalSteps - 1));
  }

  void _stepForward() {
    _pause();
    setState(() => _step = (_step + 1).clamp(0, _totalSteps - 1));
  }

  void _reset() {
    _pause();
    setState(() => _step = 0);
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
      final suggestedName = widget.aida.title.replaceAll(RegExp(r'[^\w\s-]'), '_');
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
    final stitchCount = widget.aida.stitches.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.aida.title} — ${widget.threadName}'),
        actions: [
          _exporting
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Tooltip(
                  message: 'Download GIF',
                  child: IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: _exportGif,
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          // ── Canvas ───────────────────────────────────────────────────────
          Expanded(
            child: CustomPaint(
              painter: StitchDemoPainter(
                aida: widget.aida,
                currentStep: _step,
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
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Step counter + progress
                Row(
                  children: [
                    Text(
                      'Step $_step / $stitchCount',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      '${_fps.round()} fps',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: stitchCount == 0 ? 0 : _step / stitchCount,
                  minHeight: 2,
                ),
                const SizedBox(height: 4),
                // Playback row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Reset
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      tooltip: 'Reset',
                      onPressed: _step > 0 ? _reset : null,
                    ),
                    // Step back
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Step back',
                      onPressed: _step > 0 ? _stepBack : null,
                    ),
                    // Play / pause
                    FilledButton.icon(
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      label: Text(_playing ? 'Pause' : 'Play'),
                      onPressed: _playing ? _pause : _play,
                    ),
                    // Step forward
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Step forward',
                      onPressed:
                          _step < _totalSteps - 1 ? _stepForward : null,
                    ),
                    // Skip to end
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Jump to end',
                      onPressed: _step < _totalSteps - 1
                          ? () {
                              _pause();
                              setState(() => _step = _totalSteps - 1);
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
                        min: 1,
                        max: 16,
                        divisions: 15,
                        value: _fps,
                        label: '${_fps.round()} fps',
                        onChanged: (v) {
                          setState(() => _fps = v);
                          if (_playing) _play(); // restart with new speed
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
