import 'package:flutter/material.dart';
import '../models/snippet.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

/// Renders a [Snippet] as a small preview image.
class SnippetThumbnail extends StatelessWidget {
  final Snippet snippet;
  final double size;
  final Color aidaColor;

  const SnippetThumbnail({
    super.key,
    required this.snippet,
    this.size = 80,
    this.aidaColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SnippetThumbnailPainter(
          snippet: snippet,
          aidaColor: aidaColor,
        ),
      ),
    );
  }
}

class _SnippetThumbnailPainter extends CustomPainter {
  final Snippet snippet;
  final Color aidaColor;

  const _SnippetThumbnailPainter({
    required this.snippet,
    required this.aidaColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background with aida colour.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = aidaColor,
    );

    if (snippet.width == 0 || snippet.height == 0) return;

    final threadMap = {for (final t in snippet.threads) t.dmcCode: t};

    final cellW = size.width / snippet.width;
    final cellH = size.height / snippet.height;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final stitch in snippet.stitches) {
      final thread = _threadForStitch(stitch, threadMap);
      if (thread == null) continue;
      paint.color = thread.color;
      _drawStitch(canvas, stitch, cellW, cellH, paint);
    }
  }

  Thread? _threadForStitch(Stitch stitch, Map<String, Thread> threadMap) =>
      threadMap[stitch.threadId];

  void _drawStitch(
    Canvas canvas,
    Stitch stitch,
    double cellW,
    double cellH,
    Paint paint,
  ) {
    switch (stitch) {
      case FullStitch(:final x, :final y):
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
          paint,
        );
      case HalfStitch(:final x, :final y):
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
          paint,
        );
      case QuarterStitch(:final x, :final y):
        canvas.drawRect(
          Rect.fromLTWH(x * cellW + cellW * 0.25, y * cellH + cellH * 0.25,
              cellW * 0.5, cellH * 0.5),
          paint,
        );
      case HalfCrossStitch(:final x, :final y):
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
          paint,
        );
      case QuarterCrossStitch(:final x, :final y):
        canvas.drawRect(
          Rect.fromLTWH(x * cellW + cellW * 0.25, y * cellH + cellH * 0.25,
              cellW * 0.5, cellH * 0.5),
          paint,
        );
      case BackStitch(:final x1, :final y1, :final x2, :final y2):
        final strokePaint = Paint()
          ..color = paint.color
          ..strokeWidth = (cellW * 0.2).clamp(0.5, 2.0)
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(x1 * cellW, y1 * cellH),
          Offset(x2 * cellW, y2 * cellH),
          strokePaint,
        );
    }
  }

  @override
  bool shouldRepaint(_SnippetThumbnailPainter old) =>
      old.snippet != snippet || old.aidaColor != aidaColor;
}
