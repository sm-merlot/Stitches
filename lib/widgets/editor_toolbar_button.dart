part of 'editor_toolbar.dart';

// ─── Toolbar button ───────────────────────────────────────────────────────────
// Unified ~34×34 button for all toolbar actions.

class _ToolbarButton extends StatelessWidget {
  final bool selected;
  final Widget Function(Color contentColor) builder;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? activeColor; // defaults to theme primary

  const _ToolbarButton({
    required this.selected,
    required this.builder,
    required this.tooltip,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? Theme.of(context).colorScheme.primary;
    final disabled = onTap == null;
    final bgColor = !disabled && selected ? color : Colors.transparent;
    final borderColor = disabled
        ? Colors.grey.shade200
        : selected
            ? color
            : Colors.grey.shade300;
    final contentColor = disabled
        ? Colors.grey.shade400
        : selected
            ? Colors.white
            : Colors.grey.shade600;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Center(child: builder(contentColor)),
        ),
      ),
    );
  }
}

// ─── Eraser size button ────────────────────────────────────────────────────────
// Looks like _ToolbarButton but opens a popup list of sizes 1–10.

class _EraserSizeButton extends StatelessWidget {
  final int eraserSize;
  final bool selected;
  final ValueChanged<int> onSelected;

  const _EraserSizeButton({
    required this.eraserSize,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bgColor = selected ? primary : Colors.transparent;
    final borderColor = selected ? primary : Colors.grey.shade300;
    final textColor = selected ? Colors.white : Colors.grey.shade600;

    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: onSelected,
      offset: const Offset(0, 36),
      itemBuilder: (_) => [
        for (var sz = 1; sz <= 10; sz++)
          PopupMenuItem<int>(
            value: sz,
            child: Text(
              '$sz',
              style: TextStyle(
                fontWeight: sz == eraserSize ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 50,
        height: 34,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$eraserSize',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: textColor),
          ],
        ),
      ),
    );
  }
}

// ─── Stitch icon painter ──────────────────────────────────────────────────────
// Single painter + six top-level draw functions replace the old per-type classes.

typedef _DrawFn = void Function(Canvas canvas, Size size, Color color);

class _StitchIconPainter extends CustomPainter {
  final Color color;
  final _DrawFn draw;
  const _StitchIconPainter({required this.color, required this.draw});

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size, color);

  @override
  bool shouldRepaint(_StitchIconPainter old) =>
      old.color != color || !identical(old.draw, draw);
}

void _drawFullStitch(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(pad, pad), Offset(size.width - pad, size.height - pad), p);
  canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), p);
  canvas.drawRect(
    Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
    Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke,
  );
}

void _drawHalfForward(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), p);
  canvas.drawRect(
    Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
    Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke,
  );
}

void _drawHalfBackward(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(pad, pad), Offset(size.width - pad, size.height - pad), p);
  canvas.drawRect(
    Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
    Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke,
  );
}

void _drawHalfCross(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final midX = size.width / 2;
  canvas.drawLine(Offset(pad, pad), Offset(midX, size.height - pad), p);
  canvas.drawLine(Offset(midX, pad), Offset(pad, size.height - pad), p);
  canvas.drawLine(
    Offset(midX, pad - 2),
    Offset(midX, size.height - pad + 2),
    Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.0,
  );
}

void _drawQuarterDiag(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final cx = size.width / 2;
  final cy = size.height / 2;
  canvas.drawLine(Offset(pad, pad), Offset(cx, cy), p);
  final gp = Paint()
    ..color = color.withValues(alpha: 0.25)
    ..strokeWidth = 0.8;
  canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gp);
  canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gp);
}

void _drawQuarterCross(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final cx = size.width / 2;
  final cy = size.height / 2;
  canvas.drawLine(Offset(pad, pad), Offset(cx - 1, cy - 1), p);
  canvas.drawLine(Offset(cx - 1, pad), Offset(pad, cy - 1), p);
  final gp = Paint()
    ..color = color.withValues(alpha: 0.25)
    ..strokeWidth = 0.8;
  canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gp);
  canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gp);
}

// ─── Save as snippet ──────────────────────────────────────────────────────────

void _saveAsSnippet(BuildContext context, WidgetRef ref) {
  ref.read(editorProvider.notifier).saveSelectionAsSnippet('');
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Saved as snippet'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SnippetsPanel(),
        ),
      ),
    ),
  );
  Future.delayed(const Duration(seconds: 3), messenger.hideCurrentSnackBar);
}
