import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/color_picker_screen.dart';

const _aidaPresets = [
  (label: 'White',         color: Color(0xFFFFFFFF)),
  (label: 'Antique white', color: Color(0xFFFAF0DC)),
  (label: 'Cream',         color: Color(0xFFFFF8DC)),
  (label: 'Light grey',    color: Color(0xFFD8D8D8)),
  (label: 'Mid grey',      color: Color(0xFF888888)),
  (label: 'Charcoal',      color: Color(0xFF404040)),
  (label: 'Black',         color: Color(0xFF1A1A1A)),
  (label: 'Navy',          color: Color(0xFF1B2A4A)),
  (label: 'Sage green',    color: Color(0xFF7A9E7E)),
  (label: 'Sky blue',      color: Color(0xFFB0C8E0)),
  (label: 'Dusty rose',    color: Color(0xFFD4A0A0)),
  (label: 'Burgundy',      color: Color(0xFF6B1A1A)),
];

class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final surface = theme.colorScheme.surface;

    final vDivider = Container(width: 1, height: 32, color: theme.dividerColor);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
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
          // ── LEFT: Cursor modes ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeButton(
                  icon: Icons.draw_outlined,
                  tooltip: 'Draw  [D]',
                  active: state.drawingMode == DrawingMode.draw,
                  activeColor: primary,
                  onTap: () => notifier.setDrawingMode(DrawingMode.draw),
                ),
                const SizedBox(width: 2),
                _ModeButton(
                  icon: Icons.auto_fix_normal,
                  tooltip: 'Erase  [E]',
                  active: state.drawingMode == DrawingMode.erase,
                  activeColor: theme.colorScheme.error,
                  onTap: () => notifier.setDrawingMode(DrawingMode.erase),
                ),
                const SizedBox(width: 2),
                _ModeButton(
                  icon: Icons.pan_tool_outlined,
                  tooltip: 'Pan  [P or Space]',
                  active: state.drawingMode == DrawingMode.pan,
                  activeColor: primary,
                  onTap: () => notifier.setDrawingMode(DrawingMode.pan),
                ),
                const SizedBox(width: 2),
                _ModeButton(
                  icon: Icons.colorize_outlined,
                  tooltip: 'Pick colour  [C]',
                  active: state.drawingMode == DrawingMode.colorPicker,
                  activeColor: primary,
                  onTap: () => notifier.setDrawingMode(DrawingMode.colorPicker),
                ),
                const SizedBox(width: 2),
                _ModeButton(
                  icon: Icons.select_all_outlined,
                  tooltip: 'Select  [S]',
                  active: state.drawingMode == DrawingMode.select ||
                      state.drawingMode == DrawingMode.paste,
                  activeColor: primary,
                  onTap: () => notifier.setDrawingMode(DrawingMode.select),
                ),
              ],
            ),
          ),
          vDivider,

          // ── MIDDLE: Stitch tools (scrollable, fills remaining space) ──────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Builder(builder: (context) {
                final isDrawMode = state.drawingMode == DrawingMode.draw;
                return Row(
                  children: [
                    _StitchIconButton(
                      tooltip: 'Full stitch  [1]',
                      selected: state.currentTool == DrawingTool.fullStitch,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.fullStitch) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _FullStitchIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _StitchIconButton(
                      tooltip: 'Half diagonal /  [2]',
                      selected: state.currentTool == DrawingTool.halfForward,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.halfForward) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _HalfForwardIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _StitchIconButton(
                      tooltip: 'Half diagonal \\  [3]',
                      selected: state.currentTool == DrawingTool.halfBackward,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.halfBackward) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _HalfBackwardIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _StitchIconButton(
                      tooltip: 'Half-cell cross (X in ½ cell)  [4]',
                      selected: state.currentTool == DrawingTool.halfCross,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.halfCross) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _HalfCrossIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _StitchIconButton(
                      tooltip: 'Quarter diagonal (auto-corner)  [5]',
                      selected: state.currentTool == DrawingTool.quarterDiag,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.quarterDiag) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _QuarterDiagIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _StitchIconButton(
                      tooltip: 'Quarter-cell cross / petit point  [6]',
                      selected: state.currentTool == DrawingTool.quarterCross,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.quarterCross) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                      painterBuilder: (c) => _QuarterCrossIconPainter(color: c),
                    ),
                    const SizedBox(width: 4),
                    _ToolButton(
                      icon: Icons.gesture,
                      tooltip: 'Backstitch  [7]',
                      selected: state.currentTool == DrawingTool.backstitch,
                      onTap: isDrawMode ? () => notifier.setTool(DrawingTool.backstitch) : null,
                      primary: primary,
                      onPrimary: onPrimary,
                    ),
                  ],
                );
              }),
            ),
          ),
          vDivider,

          // ── RIGHT: Colour + swatches + palette + undo/redo ────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QuickSwatches(state: state),
                _ColorSwatch(state: state),
                vDivider,
                const SizedBox(width: 4),
                const _PaletteButton(),
                const SizedBox(width: 4),
                vDivider,
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Copy  [Cmd+C]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: state.selectionRect != null && state.selectedStitches.isNotEmpty
                        ? () => notifier.copySelection()
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'Cut  [Cmd+X]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.cut_outlined),
                    onPressed: state.selectionRect != null && state.selectedStitches.isNotEmpty
                        ? () => notifier.cutSelection()
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'Paste  [Cmd+V]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.paste_outlined),
                    onPressed: () => notifier.enterPasteMode(),
                  ),
                ),
                Tooltip(
                  message: 'Delete selection  [Del]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      color: state.selectionRect != null && state.selectedStitches.isNotEmpty
                          ? theme.colorScheme.error
                          : null,
                    ),
                    onPressed: state.selectionRect != null && state.selectedStitches.isNotEmpty
                        ? () => notifier.deleteSelection()
                        : null,
                  ),
                ),
                vDivider,
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Undo  [Cmd+Z]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo),
                    onPressed: state.canUndo ? () => notifier.undo() : null,
                  ),
                ),
                Tooltip(
                  message: 'Redo  [Cmd+Shift+Z]',
                  child: IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.redo),
                    onPressed: state.canRedo ? () => notifier.redo() : null,
                  ),
                ),
                vDivider,
                const SizedBox(width: 4),
                const _AidaButton(),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Colour swatch ────────────────────────────────────────────────────────────

class _ColorSwatch extends ConsumerWidget {
  final EditorState state;

  const _ColorSwatch({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useDmc = ref.watch(settingsProvider).useDmc;
    final thread = state.selectedThread;
    final displayCode = thread == null
        ? '—'
        : useDmc
            ? thread.dmcCode
            : (dmcColorByCode(thread.dmcCode)?.anchorCode ?? thread.dmcCode);
    final tooltipLabel = thread != null
        ? 'Thread: $displayCode – ${thread.name}'
        : 'No thread selected';

    return Tooltip(
      message: tooltipLabel,
      child: InkWell(
        onTap: () => showColorPicker(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThreadSwatch(thread: thread, size: 24),
              const SizedBox(width: 5),
              Text(
                displayCode,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Palette button ───────────────────────────────────────────────────────────

class _PaletteButton extends StatelessWidget {
  const _PaletteButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Thread palette',
      child: IconButton(
        icon: const Icon(Icons.palette_outlined, size: 20),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _PaletteDialog(),
        ),
      ),
    );
  }
}

// ─── Palette dialog ───────────────────────────────────────────────────────────

class _PaletteDialog extends ConsumerWidget {
  const _PaletteDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final threads = state.pattern.threads;
    final theme = Theme.of(context);

    return Dialog(
      clipBehavior: Clip.hardEdge,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text('Threads in Pattern', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Thread list
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No threads yet.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: threads.length,
                  itemExtent: 48,
                  itemBuilder: (_, i) {
                    final t = threads[i];
                    final displayCode = useDmc
                        ? t.dmcCode
                        : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
                    final isSelected = state.selectedThreadId == t.dmcCode;
                    return ListTile(
                      dense: true,
                      leading: GestureDetector(
                        onTap: () => _showSymbolPicker(context, ref, t),
                        child: _ThreadSwatch(thread: t, size: 24),
                      ),
                      title: Text('$displayCode – ${t.name}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(Icons.check,
                                size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Change symbol',
                            child: GestureDetector(
                              onTap: () => _showSymbolPicker(context, ref, t),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: t.color,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  t.symbol.isNotEmpty ? t.symbol : '?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: t.color.computeLuminance() > 0.35
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      selected: isSelected,
                      onTap: () {
                        ref
                            .read(editorProvider.notifier)
                            .setSelectedThread(t.dmcCode);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            // Add colour — opens picker on top without closing this dialog
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 20),
              title: const Text('Add colour…'),
              onTap: () => showColorPicker(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showSymbolPicker(BuildContext context, WidgetRef ref, Thread t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SymbolPickerDialog(
        thread: t,
        onSelect: (s) {
          ref.read(editorProvider.notifier).changeThreadSymbol(t.dmcCode, s);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

// ─── Symbol picker dialog ─────────────────────────────────────────────────────

class _SymbolPickerDialog extends StatefulWidget {
  final Thread thread;
  final ValueChanged<String> onSelect;
  const _SymbolPickerDialog({required this.thread, required this.onSelect});

  @override
  State<_SymbolPickerDialog> createState() => _SymbolPickerDialogState();
}

class _SymbolPickerDialogState extends State<_SymbolPickerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill if the current symbol is a custom (non-preset) one
    final current = widget.thread.symbol;
    _controller = TextEditingController(
      text: kPatternSymbols.contains(current) ? '' : current,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final t = widget.thread;
    final textColor =
        t.color.computeLuminance() > 0.35 ? Colors.black : Colors.white;
    final customText = _controller.text.trim();

    return AlertDialog(
      title: Text('${t.dmcCode} – ${t.name}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preset symbols grid ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kPatternSymbols.map((s) {
                    final isSelected =
                        s == t.symbol && customText.isEmpty;
                    return GestureDetector(
                      onTap: () => widget.onSelect(s),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: t.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected ? primary : Colors.grey.shade300,
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // ── Custom symbol entry ──────────────────────────────────────────
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'Custom symbol',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) widget.onSelect(v.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Live preview in thread colour
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: customText.isNotEmpty ? t.color : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: customText.isNotEmpty
                          ? primary
                          : Colors.grey.shade300,
                      width: customText.isNotEmpty ? 2.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              customText.isNotEmpty ? () => widget.onSelect(customText) : null,
          child: const Text('Use custom'),
        ),
      ],
    );
  }
}

// ─── Quick swatches (last 5 used) ────────────────────────────────────────────

class _QuickSwatches extends ConsumerWidget {
  final EditorState state;
  const _QuickSwatches({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Exclude the currently selected thread; most recent rightmost (left-to-right order).
    final displayIds = state.recentThreadIds
        .where((id) => id != state.selectedThreadId)
        .toList()
        .reversed
        .toList();
    if (displayIds.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 4),
        ...displayIds.map((id) {
          final thread = state.pattern.threadByCode(id);
          if (thread == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: '${thread.dmcCode} – ${thread.name}',
              child: GestureDetector(
                onTap: () =>
                    ref.read(editorProvider.notifier).setSelectedThread(id),
                child: _ThreadSwatch(thread: thread, size: 28),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Thread colour swatch with symbol overlay ─────────────────────────────────

class _ThreadSwatch extends StatelessWidget {
  final Thread? thread;
  final double size;

  const _ThreadSwatch({required this.thread, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final color = t?.color ?? Colors.grey.shade300;
    final symbol = t?.symbol ?? '';
    final textColor = color.computeLuminance() > 0.35 ? Colors.black : Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.17),
        border: Border.all(color: Colors.grey.shade400, width: 1),
      ),
      alignment: Alignment.center,
      child: symbol.isNotEmpty
          ? Text(
              symbol,
              style: TextStyle(
                fontSize: size * 0.46,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1.0,
              ),
            )
          : null,
    );
  }
}

// ─── Aida colour button ───────────────────────────────────────────────────────

class _AidaButton extends ConsumerWidget {
  const _AidaButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aidaColor = ref.watch(editorProvider).pattern.aidaColor;
    final iconColor = aidaColor.computeLuminance() > 0.4
        ? Colors.black54
        : Colors.white70;

    return Tooltip(
      message: 'Aida fabric colour',
      child: GestureDetector(
        onTap: () => _showPicker(context, ref, aidaColor),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: aidaColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
          child: Icon(Icons.grid_on, size: 17, color: iconColor),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref, Color current) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aida fabric colour'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _aidaPresets.map((p) {
            final selected = p.color.toARGB32() == current.toARGB32();
            return Tooltip(
              message: p.label,
              child: GestureDetector(
                onTap: () {
                  ref.read(editorProvider.notifier).setAidaColor(p.color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade400,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: p.color.computeLuminance() > 0.4
                              ? Colors.black54
                              : Colors.white70,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─── Mode button (draw / erase / pan) ────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? activeColor : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color: active ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ─── Stitch tool button ───────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
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
    final disabled = onTap == null;
    final bgColor = !disabled && selected ? primary : Colors.transparent;
    final borderColor = disabled
        ? Colors.grey.shade200
        : selected
            ? primary
            : Colors.grey.shade300;
    final contentColor = disabled
        ? Colors.grey.shade400
        : selected
            ? onPrimary
            : Colors.grey.shade700;

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
          child: Center(
            child: icon != null
                ? Icon(icon, size: 17, color: contentColor)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: contentColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Custom painted stitch tool button (shared) ──────────────────────────────

class _StitchIconButton extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final Color primary;
  final Color onPrimary;
  final CustomPainter Function(Color color) painterBuilder;

  const _StitchIconButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.primary,
    required this.onPrimary,
    required this.painterBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final iconColor = disabled
        ? Colors.grey.shade400
        : selected
            ? onPrimary
            : Colors.grey.shade700;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: !disabled && selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: disabled
                  ? Colors.grey.shade200
                  : selected
                      ? primary
                      : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: CustomPaint(painter: painterBuilder(iconColor)),
        ),
      ),
    );
  }
}

// ─── Stitch icon painters ─────────────────────────────────────────────────────

class _FullStitchIconPainter extends CustomPainter {
  final Color color;
  const _FullStitchIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Full X
    canvas.drawLine(Offset(pad, pad), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), paint);
    // Cell outline
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_FullStitchIconPainter old) => old.color != color;
}

class _HalfForwardIconPainter extends CustomPainter {
  final Color color;
  const _HalfForwardIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Forward diagonal /
    canvas.drawLine(Offset(size.width - pad, pad), Offset(pad, size.height - pad), paint);
    // Cell outline
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_HalfForwardIconPainter old) => old.color != color;
}

class _HalfBackwardIconPainter extends CustomPainter {
  final Color color;
  const _HalfBackwardIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Backward diagonal \
    canvas.drawLine(Offset(pad, pad), Offset(size.width - pad, size.height - pad), paint);
    // Cell outline
    canvas.drawRect(
      Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad),
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_HalfBackwardIconPainter old) => old.color != color;
}

class _HalfCrossIconPainter extends CustomPainter {
  final Color color;
  const _HalfCrossIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final midX = size.width / 2;
    canvas.drawLine(Offset(pad, pad), Offset(midX, size.height - pad), paint);
    canvas.drawLine(Offset(midX, pad), Offset(pad, size.height - pad), paint);
    canvas.drawLine(
        Offset(midX, pad - 2),
        Offset(midX, size.height - pad + 2),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(_HalfCrossIconPainter old) => old.color != color;
}

class _QuarterDiagIconPainter extends CustomPainter {
  final Color color;
  const _QuarterDiagIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(pad, pad), Offset(cx, cy), paint);
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gridPaint);
    canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gridPaint);
  }

  @override
  bool shouldRepaint(_QuarterDiagIconPainter old) => old.color != color;
}

class _QuarterCrossIconPainter extends CustomPainter {
  final Color color;
  const _QuarterCrossIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(pad, pad), Offset(cx - 1, cy - 1), paint);
    canvas.drawLine(Offset(cx - 1, pad), Offset(pad, cy - 1), paint);
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(cx, pad), Offset(cx, size.height - pad), gridPaint);
    canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), gridPaint);
  }

  @override
  bool shouldRepaint(_QuarterCrossIconPainter old) => old.color != color;
}
