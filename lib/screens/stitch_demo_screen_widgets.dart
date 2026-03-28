part of 'stitch_demo_screen.dart';

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
