import 'dart:math';

import 'package:flutter/material.dart';

import '../data/dmc_colors.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../services/ai/ai_provider.dart';

/// Full-screen preview of an AI-scanned pattern.
///
/// Pops with a [CrossStitchPattern] if the user taps "Use Pattern",
/// or null if they cancel.
class PatternScanPreviewScreen extends StatelessWidget {
  final PatternScanResult result;
  final String patternName;

  const PatternScanPreviewScreen({
    super.key,
    required this.result,
    required this.patternName,
  });

  // ── Conversion ─────────────────────────────────────────────────────────────

  CrossStitchPattern _buildPattern() {
    final threads = result.threads.map((t) {
      final dmc = dmcColorByCode(t.dmcCode);
      final color = dmc?.color ?? _hexColor(t.colorHex);
      return Thread(dmcCode: t.dmcCode, name: t.name, color: color);
    }).toList();

    final stitches = <Stitch>[];
    for (final s in result.stitches) {
      switch (s.type) {
        case 'half_forward':
          stitches
              .add(HalfStitch(x: s.x, y: s.y, isForward: true, threadId: s.dmcCode));
        case 'half_backward':
          stitches.add(
              HalfStitch(x: s.x, y: s.y, isForward: false, threadId: s.dmcCode));
        case 'backstitch':
          if (s.x2 != null && s.y2 != null) {
            stitches.add(BackStitch(
              x1: s.x.toDouble(),
              y1: s.y.toDouble(),
              x2: s.x2!.toDouble(),
              y2: s.y2!.toDouble(),
              threadId: s.dmcCode,
            ));
          }
        default: // 'full' and anything unrecognised
          stitches.add(FullStitch(x: s.x, y: s.y, threadId: s.dmcCode));
      }
    }

    return CrossStitchPattern(
      name: patternName,
      width: result.width,
      height: result.height,
      threads: threads,
      stitches: stitches,
    );
  }

  static Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '').padRight(6, '0');
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    return Color.fromARGB(255, r, g, b);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullStitches =
        result.stitches.where((s) => s.type != 'backstitch').length;
    final backstitches =
        result.stitches.where((s) => s.type == 'backstitch').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned Pattern'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_buildPattern()),
            child: const Text('Use Pattern'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning banner
          if (result.warning != null && result.warning!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.warning!,
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),

          // Canvas preview
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 300,
              child: _PatternPreview(result: result),
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          Row(
            children: [
              _Stat(label: 'Size',
                  value: '${result.width} × ${result.height}'),
              _Stat(label: 'Threads',
                  value: '${result.threads.length}'),
              _Stat(label: 'Stitches', value: '$fullStitches'),
              if (backstitches > 0)
                _Stat(label: 'Backstitch', value: '$backstitches'),
            ],
          ),
          const SizedBox(height: 16),

          // Thread list
          Text('Threads', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...result.threads.map((t) {
            final dmc = dmcColorByCode(t.dmcCode);
            final color = dmc?.color ?? _hexColor(t.colorHex);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.grey.shade300, width: 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${t.dmcCode}  –  ${t.name}',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),
          Text(
            'AI-generated patterns may contain errors. '
            'Review and correct in the editor after importing.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

// ── Mini canvas preview ───────────────────────────────────────────────────────

class _PatternPreview extends StatelessWidget {
  final PatternScanResult result;
  const _PatternPreview({required this.result});

  @override
  Widget build(BuildContext context) {
    // Build colour lookup from dmcCode → Color.
    final colors = <String, Color>{};
    for (final t in result.threads) {
      final dmc = dmcColorByCode(t.dmcCode);
      colors[t.dmcCode] =
          dmc?.color ?? PatternScanPreviewScreen._hexColor(t.colorHex);
    }

    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        painter: _PreviewPainter(result: result, colors: colors),
        size: constraints.biggest,
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final PatternScanResult result;
  final Map<String, Color> colors;

  _PreviewPainter({required this.result, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // Aida background
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFFAF7F0));

    if (result.width == 0 || result.height == 0) return;

    final cellW = size.width / result.width;
    final cellH = size.height / result.height;
    final cellSize = min(cellW, cellH);

    // Centre the grid
    final offsetX = (size.width - cellSize * result.width) / 2;
    final offsetY = (size.height - cellSize * result.height) / 2;

    for (final stitch in result.stitches) {
      if (stitch.type == 'backstitch') continue;
      final color = colors[stitch.dmcCode] ?? Colors.black;
      final rect = Rect.fromLTWH(
        offsetX + stitch.x * cellSize,
        offsetY + stitch.y * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(rect, Paint()..color = color);
    }

    // Draw backstitches
    for (final stitch in result.stitches) {
      if (stitch.type != 'backstitch') continue;
      if (stitch.x2 == null || stitch.y2 == null) continue;
      final color = colors[stitch.dmcCode] ?? Colors.black;
      canvas.drawLine(
        Offset(offsetX + stitch.x * cellSize, offsetY + stitch.y * cellSize),
        Offset(offsetX + stitch.x2! * cellSize,
            offsetY + stitch.y2! * cellSize),
        Paint()
          ..color = color
          ..strokeWidth = max(1.0, cellSize * 0.15)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => false;
}

// ── Stat chip ────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: const EdgeInsets.only(right: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }
}
