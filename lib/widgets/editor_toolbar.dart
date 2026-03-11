import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor_provider.dart';

class EditorToolbar extends ConsumerWidget {
  final VoidCallback onOpenColorPicker;

  const EditorToolbar({super.key, required this.onOpenColorPicker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final surface = theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      height: 56,
      child: Row(
        children: [
          // ── Stitch Tool Buttons ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _ToolButton(
                    label: 'X',
                    tooltip: 'Full stitch  [1]',
                    selected: state.currentTool == DrawingTool.fullStitch,
                    onTap: () => notifier.setTool(DrawingTool.fullStitch),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _ToolButton(
                    label: '/',
                    tooltip: 'Half diagonal /  [2]',
                    selected: state.currentTool == DrawingTool.halfForward,
                    onTap: () => notifier.setTool(DrawingTool.halfForward),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _ToolButton(
                    label: '\\',
                    tooltip: 'Half diagonal \\  [3]',
                    selected: state.currentTool == DrawingTool.halfBackward,
                    onTap: () => notifier.setTool(DrawingTool.halfBackward),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _HalfCrossToolButton(
                    tooltip: 'Half-cell cross (X in ½ cell)  [4]',
                    selected: state.currentTool == DrawingTool.halfCross,
                    onTap: () => notifier.setTool(DrawingTool.halfCross),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _QuarterDiagToolButton(
                    tooltip: 'Quarter diagonal (auto-detect corner)  [5]',
                    selected: state.currentTool == DrawingTool.quarterDiag,
                    onTap: () => notifier.setTool(DrawingTool.quarterDiag),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _QuarterCrossToolButton(
                    tooltip: 'Quarter-cell cross / petit point  [6]',
                    selected: state.currentTool == DrawingTool.quarterCross,
                    onTap: () => notifier.setTool(DrawingTool.quarterCross),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _ToolButton(
                    icon: Icons.gesture,
                    tooltip: 'Backstitch  [7]',
                    selected: state.currentTool == DrawingTool.backstitch,
                    onTap: () => notifier.setTool(DrawingTool.backstitch),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                  const SizedBox(width: 4),
                  _ToolButton(
                    icon: Icons.pan_tool_outlined,
                    tooltip: 'Navigate / Pan  [Space]',
                    selected: state.currentTool == DrawingTool.navigate,
                    onTap: () => notifier.setTool(DrawingTool.navigate),
                    primary: primary,
                    onPrimary: onPrimary,
                  ),
                ],
              ),
            ),
          ),

          // ── Right-side Controls ────────────────────────────────────────────
          Container(
            width: 1,
            height: 32,
            color: Theme.of(context).dividerColor,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Erase toggle
                Tooltip(
                  message: state.drawingMode == DrawingMode.draw
                      ? 'Draw mode  [E to toggle]'
                      : 'Erase mode  [E to toggle]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    style: state.drawingMode == DrawingMode.erase
                        ? IconButton.styleFrom(
                            backgroundColor:
                                theme.colorScheme.errorContainer,
                            foregroundColor:
                                theme.colorScheme.onErrorContainer,
                          )
                        : null,
                    icon: Icon(
                      state.drawingMode == DrawingMode.draw
                          ? Icons.edit_outlined
                          : Icons.delete_outline,
                    ),
                    onPressed: () => notifier.toggleDrawingMode(),
                  ),
                ),

                // Colour swatch / thread picker
                Tooltip(
                  message: state.selectedThread != null
                      ? 'Thread: ${state.selectedThread!.code} – ${state.selectedThread!.name}'
                      : 'No thread selected',
                  child: InkWell(
                    onTap: onOpenColorPicker,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: state.selectedThread?.color ??
                                  Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.grey.shade400, width: 1),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.selectedThread?.code ?? '—',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Undo
                Tooltip(
                  message: 'Undo  [Cmd+Z]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo),
                    onPressed:
                        state.canUndo ? () => notifier.undo() : null,
                  ),
                ),

                // Redo
                Tooltip(
                  message: 'Redo  [Cmd+Shift+Z]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.redo),
                    onPressed:
                        state.canRedo ? () => notifier.redo() : null,
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

// ─── Tool Button ─────────────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;
  final Color onPrimary;

  const _ToolButton({
    this.label,
    this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.primary,
    required this.onPrimary,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? primary : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon,
                    size: 18,
                    color: selected ? onPrimary : Colors.grey.shade700)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? onPrimary : Colors.grey.shade700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Custom painted tool buttons ──────────────────────────────────────────────

class _HalfCrossToolButton extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;
  final Color onPrimary;

  const _HalfCrossToolButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.primary,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? primary : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: CustomPaint(
            painter: _HalfCrossIconPainter(
              color: selected ? onPrimary : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _HalfCrossIconPainter extends CustomPainter {
  final Color color;
  const _HalfCrossIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const pad = 5.0;
    final midX = size.width / 2;
    // X in the left half only
    canvas.drawLine(Offset(pad, pad), Offset(midX, size.height - pad), paint);
    canvas.drawLine(Offset(midX, pad), Offset(pad, size.height - pad), paint);
    // Dividing line in the middle
    canvas.drawLine(
        Offset(midX, pad - 2),
        Offset(midX, size.height - pad + 2),
        Paint()
          ..color = color.withValues(alpha:0.35)
          ..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(_HalfCrossIconPainter old) => old.color != color;
}

class _QuarterDiagToolButton extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;
  final Color onPrimary;

  const _QuarterDiagToolButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.primary,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? primary : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: CustomPaint(
            painter: _QuarterDiagIconPainter(
              color: selected ? onPrimary : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuarterDiagIconPainter extends CustomPainter {
  final Color color;
  const _QuarterDiagIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const pad = 5.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Top-left diagonal to center (representing auto-quadrant quarter stitch)
    canvas.drawLine(Offset(pad, pad), Offset(cx, cy), paint);
    // Show the 4-quadrant grid faintly
    final gridPaint = Paint()
      ..color = color.withValues(alpha:0.25)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gridPaint);
    canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gridPaint);
  }

  @override
  bool shouldRepaint(_QuarterDiagIconPainter old) => old.color != color;
}

class _QuarterCrossToolButton extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;
  final Color onPrimary;

  const _QuarterCrossToolButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.primary,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? primary : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: CustomPaint(
            painter: _QuarterCrossIconPainter(
              color: selected ? onPrimary : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuarterCrossIconPainter extends CustomPainter {
  final Color color;
  const _QuarterCrossIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const pad = 5.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Small X in top-left quadrant
    canvas.drawLine(Offset(pad, pad), Offset(cx - 1, cy - 1), paint);
    canvas.drawLine(Offset(cx - 1, pad), Offset(pad, cy - 1), paint);
    // Faint grid showing the 4 quadrants
    final gridPaint = Paint()
      ..color = color.withValues(alpha:0.25)
      ..strokeWidth = 0.8;
    canvas.drawLine(
        Offset(cx, pad), Offset(cx, size.height - pad), gridPaint);
    canvas.drawLine(
        Offset(pad, cy), Offset(size.width - pad, cy), gridPaint);
  }

  @override
  bool shouldRepaint(_QuarterCrossIconPainter old) => old.color != color;
}

