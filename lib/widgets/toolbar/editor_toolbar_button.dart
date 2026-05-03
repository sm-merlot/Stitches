part of 'editor_toolbar.dart';

// ─── Toolbar button ───────────────────────────────────────────────────────────
// Unified ~34×34 button for all toolbar actions.

class _ToolbarButton extends StatelessWidget {
  final bool selected;
  final Widget Function(Color contentColor) builder;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? activeColor; // defaults to theme primary

  const _ToolbarButton({
    required this.selected,
    required this.builder,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
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

    final size = _isTouchPlatform ? 40.0 : 34.0;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
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
        width: _isTouchPlatform ? 56 : 50,
        height: _isTouchPlatform ? 40 : 34,
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

void _drawQuarterCross(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final cx = size.width / 2;
  final cy = size.height / 2;
  // Full X in top-left quarter
  canvas.drawLine(Offset(pad, pad), Offset(cx - 1, cy - 1), p);
  canvas.drawLine(Offset(cx - 1, pad), Offset(pad, cy - 1), p);
  final gp = Paint()
    ..color = color.withValues(alpha: 0.25)
    ..strokeWidth = 0.8;
  canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gp);
  canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gp);
}

void _drawThreeQuarter(Canvas canvas, Size size, Color color) {
  const pad = 5.0;
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final cx = size.width / 2;
  final cy = size.height / 2;
  // Full diagonal
  canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), p);
  // Quarter diagonal from top-left corner to centre
  canvas.drawLine(Offset(pad, pad), Offset(cx, cy), p);
  canvas.drawRect(
    Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
    Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke,
  );
}

/// Returns the icon draw function for the given [PartialSubTool].
_DrawFn _partialSubToolIcon(PartialSubTool subTool) => switch (subTool) {
  PartialSubTool.diagonalForward  => _drawHalfForward,
  PartialSubTool.diagonalBackward => _drawHalfBackward,
  PartialSubTool.half             => _drawHalfCross,
  PartialSubTool.threeQuarter     => _drawThreeQuarter,
  PartialSubTool.quarter          => _drawQuarterCross,
};

// ─── Partial stitch button with popup ─────────────────────────────────────────

class _PartialStitchButton extends StatelessWidget {
  final bool selected;
  final PartialSubTool subTool;
  final ValueChanged<PartialSubTool> onSelect;

  const _PartialStitchButton({
    required this.selected,
    required this.subTool,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ToolbarButton(
      tooltip: _tt('Partial stitch  [2-6]'),
      selected: selected,
      onTap: () => onSelect(subTool),
      onLongPress: () => _showPopup(context, theme),
      builder: (c) => CustomPaint(
        painter: _StitchIconPainter(color: c, draw: _partialSubToolIcon(subTool)),
      ),
    );
  }

  void _showPopup(BuildContext context, ThemeData theme) {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<PartialSubTool>(
      context: context,
      position: position,
      items: [
        _popupItem(PartialSubTool.diagonalForward,  'Half diagonal /  [2]', _drawHalfForward),
        _popupItem(PartialSubTool.diagonalBackward, 'Half diagonal \\  [3]', _drawHalfBackward),
        _popupItem(PartialSubTool.half,             'Half-cell cross  [4]', _drawHalfCross),
        _popupItem(PartialSubTool.threeQuarter,     'Three-quarter  [5]', _drawThreeQuarter),
        _popupItem(PartialSubTool.quarter,          'Petit point  [6]', _drawQuarterCross),
      ],
    ).then((value) {
      if (value != null) onSelect(value);
    });
  }

  PopupMenuItem<PartialSubTool> _popupItem(
      PartialSubTool tool, String label, _DrawFn draw) {
    return PopupMenuItem(
      value: tool,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(
              painter: _StitchIconPainter(
                color: tool == subTool ? Colors.blue : Colors.grey.shade700,
                draw: draw,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontWeight: tool == subTool ? FontWeight.bold : FontWeight.normal,
          )),
        ],
      ),
    );
  }
}

// ─── Save as snippet ──────────────────────────────────────────────────────────

void _saveAsSnippet(BuildContext context, WidgetRef ref) {
  final saved = ref.read(editorProvider.notifier).saveSelectionAsSnippet('');
  if (!saved) return;
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
