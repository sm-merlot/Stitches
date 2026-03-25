import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import '../providers/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/color_picker_screen.dart';
import '../screens/stitch_demo_screen.dart';
import 'color_select_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../screens/sprite_sheet_screen.dart';
import 'snippets_panel.dart';

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
  final bool showSnippetsButton;
  final bool showSaveAsSnippetButton;
  final bool showSpriteSheetButton;
  /// When non-null, replaces the snippets button with a "Paste from snippet"
  /// button (used inside the snippet editor).
  final VoidCallback? onPasteFromSnippet;
  const EditorToolbar({
    super.key,
    this.showSnippetsButton = true,
    this.showSaveAsSnippetButton = true,
    this.showSpriteSheetButton = true,
    this.onPasteFromSnippet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    // In stitch mode show the simplified stitch toolbar
    if (state.stitchMode) {
      return const _StitchModeToolbar();
    }

    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
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
          // ── LEFT (scrollable): Cursor modes + context-sensitive tools ─────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cursor modes
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolbarButton(
                          tooltip: 'Draw  [D]',
                          selected: state.drawingMode == DrawingMode.draw,
                          onTap: () => notifier.setDrawingMode(DrawingMode.draw),
                          builder: (c) => Icon(Icons.draw_outlined, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Erase  [E]',
                          selected: state.drawingMode == DrawingMode.erase,
                          activeColor: theme.colorScheme.error,
                          onTap: () => notifier.setDrawingMode(DrawingMode.erase),
                          builder: (c) => Icon(Icons.auto_fix_normal, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Pan  [P or Space]',
                          selected: state.drawingMode == DrawingMode.pan,
                          onTap: () => notifier.setDrawingMode(DrawingMode.pan),
                          builder: (c) => Icon(Icons.pan_tool_outlined, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Pick colour  [C]',
                          selected: state.drawingMode == DrawingMode.colorPicker,
                          onTap: () => notifier.setDrawingMode(DrawingMode.colorPicker),
                          builder: (c) => Icon(Icons.colorize_outlined, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Select  [S]',
                          selected: state.drawingMode == DrawingMode.select ||
                              state.drawingMode == DrawingMode.paste,
                          onTap: () => notifier.setDrawingMode(DrawingMode.select),
                          builder: (c) => Icon(Icons.select_all_outlined, size: 17, color: c),
                        ),
                      ],
                    ),
                  ),
                  vDivider,

                  // Stitch tools (draw mode only)
                  if (state.drawingMode == DrawingMode.draw) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToolbarButton(
                            tooltip: 'Full stitch  [1]',
                            selected: state.currentTool == DrawingTool.fullStitch,
                            onTap: () => notifier.setTool(DrawingTool.fullStitch),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawFullStitch)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Half diagonal /  [2]',
                            selected: state.currentTool == DrawingTool.halfForward,
                            onTap: () => notifier.setTool(DrawingTool.halfForward),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfForward)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Half diagonal \\  [3]',
                            selected: state.currentTool == DrawingTool.halfBackward,
                            onTap: () => notifier.setTool(DrawingTool.halfBackward),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfBackward)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Half-cell cross (X in ½ cell)  [4]',
                            selected: state.currentTool == DrawingTool.halfCross,
                            onTap: () => notifier.setTool(DrawingTool.halfCross),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfCross)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Quarter diagonal (auto-corner)  [5]',
                            selected: state.currentTool == DrawingTool.quarterDiag,
                            onTap: () => notifier.setTool(DrawingTool.quarterDiag),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawQuarterDiag)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Quarter-cell cross / petit point  [6]',
                            selected: state.currentTool == DrawingTool.quarterCross,
                            onTap: () => notifier.setTool(DrawingTool.quarterCross),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawQuarterCross)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Backstitch  [7]',
                            selected: state.currentTool == DrawingTool.backstitch,
                            onTap: () => notifier.setTool(DrawingTool.backstitch),
                            builder: (c) => Icon(Icons.gesture, size: 17, color: c),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],

                  // Copy/delete — shown when a selection is active
                  if (state.drawingMode == DrawingMode.select) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                          if (showSaveAsSnippetButton)
                            Tooltip(
                              message: 'Save as snippet',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.bookmark_add_outlined),
                                onPressed: state.selectionRect != null && state.selectedStitches.isNotEmpty
                                    ? () => _saveAsSnippet(context, ref)
                                    : null,
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
                        ],
                      ),
                    ),
                    vDivider,
                  ],
                  // Cancel + opacity + save-as-snippet — shown while paste preview is active
                  if (state.drawingMode == DrawingMode.paste) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Opacity slider
                          Tooltip(
                            message: 'Paste opacity',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.opacity, size: 16),
                                SizedBox(
                                  width: 80,
                                  child: Slider(
                                    value: state.pasteOpacity,
                                    min: 0.05,
                                    max: 1.0,
                                    divisions: 19,
                                    onChanged: (v) => notifier.setPasteOpacity(v),
                                  ),
                                ),
                                Text(
                                  '${(state.pasteOpacity * 100).round()}%',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (showSaveAsSnippetButton && !state.clipboardFromSnippet)
                            Tooltip(
                              message: 'Save as snippet',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.bookmark_add_outlined),
                                onPressed: () => _saveAsSnippet(context, ref),
                              ),
                            ),
                          Tooltip(
                            message: 'Cancel paste  [Esc]',
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: theme.colorScheme.error,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Cancel'),
                              onPressed: () => notifier.cancelSelection(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],
                  // Sprite sheet button
                  if (showSpriteSheetButton)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Tooltip(
                        message: 'Import sprite sheet',
                        child: IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          icon: const FaIcon(FontAwesomeIcons.ghost),
                          onPressed: state.isFileOpen
                              ? () => _openSpriteSheet(context, ref)
                              : null,
                        ),
                      ),
                    ),
                  // Snippets / paste-from-snippet button
                  if (showSnippetsButton || onPasteFromSnippet != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: onPasteFromSnippet != null
                          ? Tooltip(
                              message: 'Paste from snippet',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.library_add_outlined),
                                onPressed: onPasteFromSnippet,
                              ),
                            )
                          : Tooltip(
                              message: 'Snippets',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.collections_bookmark_outlined),
                                onPressed: state.isFileOpen
                                    ? () => showModalBottomSheet<void>(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (_) => const SnippetsPanel(),
                                        )
                                    : null,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),

          // ── RIGHT (fixed): Colour + swatches + palette + undo/redo ────────
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
          builder: (_) => UncontrolledProviderScope(
            container: ProviderScope.containerOf(context),
            child: const _PaletteDialog(),
          ),
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
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

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
                      onLongPress: isDesktop
                          ? null
                          : () => _showReplaceDialog(context, t),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(Icons.check,
                                size: 16, color: theme.colorScheme.primary),
                          if (isDesktop)
                            Tooltip(
                              message: 'Replace colour',
                              child: InkWell(
                                onTap: () => _showReplaceDialog(context, t),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.swap_horiz,
                                    size: 16,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ),
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
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _SymbolPickerDialog(
          thread: t,
          onSelect: (s) {
            ref.read(editorProvider.notifier).changeThreadSymbol(t.dmcCode, s);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _showReplaceDialog(BuildContext context, Thread t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: t.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${t.dmcCode} – ${t.name}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
              'Replace all stitches using this colour with a different DMC colour.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                showColorPicker(context, replacingThreadId: t.dmcCode);
              },
              child: const Text('Replace colour…'),
            ),
          ],
        ),
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

// ─── Stitch mode toolbar ──────────────────────────────────────────────────────

class _StitchModeToolbar extends ConsumerWidget {
  const _StitchModeToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;

    final vDivider = Container(width: 1, height: 32, color: theme.dividerColor);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
        // Tinted border top to indicate mode
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      height: 56,
      child: Row(
        children: [
          // ── LEFT: View mode toggles + focus thread list ───────────────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Interaction mode: Pan / Select
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolbarButton(
                          tooltip: 'Pan  [P]',
                          selected: state.drawingMode == DrawingMode.pan,
                          onTap: () => notifier.setDrawingMode(DrawingMode.pan),
                          builder: (c) => Icon(Icons.pan_tool_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Select  [S]',
                          selected: state.drawingMode == DrawingMode.select,
                          onTap: state.stitchViewMode != StitchViewMode.greyed
                              ? () => notifier.setDrawingMode(DrawingMode.select)
                              : null,
                          builder: (c) => Icon(Icons.select_all_outlined, size: 16, color: c),
                        ),
                      ],
                    ),
                  ),
                  vDivider,

                  // View mode: Normal / Hidden / Greyed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolbarButton(
                          tooltip: 'Show all',
                          selected: state.stitchViewMode == StitchViewMode.normal,
                          onTap: () => notifier.setStitchViewMode(StitchViewMode.normal),
                          builder: (c) => Icon(Icons.visibility_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Hide backstitches',
                          selected: state.stitchViewMode == StitchViewMode.hidden,
                          onTap: () => notifier.setStitchViewMode(StitchViewMode.hidden),
                          builder: (c) =>
                              Icon(Icons.visibility_off_outlined, size: 16, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: 'Grey stitches',
                          selected: state.stitchViewMode == StitchViewMode.greyed,
                          onTap: () {
                            notifier.setStitchViewMode(StitchViewMode.greyed);
                            if (state.drawingMode == DrawingMode.select) {
                              notifier.setDrawingMode(DrawingMode.pan);
                            }
                          },
                          builder: (c) =>
                              Icon(Icons.invert_colors_outlined, size: 16, color: c),
                        ),
                      ],
                    ),
                  ),
                  vDivider,

                  // Focus thread selector: tap a thread to highlight only it
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Focus:',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Per-thread swatches
                        ...state.pattern.threads.map((t) {
                          final isFocused = state.stitchFocusThreadId == t.dmcCode;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: '${t.dmcCode} – ${t.name}',
                              child: GestureDetector(
                                onTap: () => notifier.setStitchFocusThread(
                                    isFocused ? null : t.dmcCode),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: t.color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isFocused
                                          ? primary
                                          : Colors.grey.shade400,
                                      width: isFocused ? 2.5 : 1,
                                    ),
                                    boxShadow: isFocused
                                        ? [
                                            BoxShadow(
                                              color: primary.withValues(alpha: 0.4),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: t.symbol.isNotEmpty
                                        ? Text(
                                            t.symbol,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: t.color.computeLuminance() > 0.35
                                                  ? Colors.black
                                                  : Colors.white,
                                              height: 1.0,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── RIGHT: Demonstrate + Palette ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                vDivider,
                const SizedBox(width: 4),
                _DemonstrateButton(state: state),
                const SizedBox(width: 4),
                vDivider,
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Thread palette',
                  child: IconButton(
                    icon: const Icon(Icons.palette_outlined, size: 20),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

// ─── Sprite sheet ─────────────────────────────────────────────────────────────

Future<void> _openSpriteSheet(BuildContext context, WidgetRef ref) async {
  final addedAny = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => const SpriteSheetScreen(),
      fullscreenDialog: true,
    ),
  );
  if ((addedAny ?? false) && context.mounted) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SnippetsPanel(),
    );
  }
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

// ─── Demonstrate button ───────────────────────────────────────────────────────

class _DemonstrateButton extends StatelessWidget {
  final EditorState state;

  const _DemonstrateButton({required this.state});

  @override
  Widget build(BuildContext context) {
    // When a selection is active, only consider stitches within it.
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : state.pattern.stitches;
    final focusId = state.stitchFocusThreadId;
    final greyed = state.stitchViewMode == StitchViewMode.greyed;
    final hasFullStitches = !greyed &&
        pool.any((s) =>
            s is FullStitch && (focusId == null || s.threadId == focusId));
    final hasSelection = state.selectionRect != null;

    return Tooltip(
      message: hasSelection
          ? 'Demonstrate selected stitches (beta)'
          : 'Demonstrate stitching (beta)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FilledButton.tonalIcon(
            icon: Icon(
              hasSelection ? Icons.play_circle_filled : Icons.play_circle_outline,
              size: 18,
            ),
            label: const Text(
              'Demo',
              style: TextStyle(fontSize: 12),
            ),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
            onPressed: hasFullStitches ? () => _onDemonstrate(context) : null,
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'β',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onDemonstrate(BuildContext context) async {
    final pattern = state.pattern;
    final focusId = state.stitchFocusThreadId;

    // Use selected region when a selection is active, otherwise all stitches.
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : pattern.stitches;
    final fullStitches = pool.whereType<FullStitch>().toList();

    // Determine the thread to demonstrate.
    Thread? thread;
    if (focusId != null) {
      // Focus thread is active — use it directly.
      thread = pattern.threadByCode(focusId);
    } else {
      // Collect threads that have at least one FullStitch in the pool.
      final threadIds = fullStitches.map((s) => s.threadId).toSet();
      final candidates =
          pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();

      if (candidates.isEmpty) return;

      if (candidates.length == 1) {
        thread = candidates.first;
      } else {
        // Multiple threads — ask the user to pick one.
        if (!context.mounted) return;
        thread = await showDialog<Thread>(
          context: context,
          builder: (_) => ColorSelectDialog(threads: candidates),
        );
        if (thread == null) return; // cancelled
      }
    }

    if (thread == null || !context.mounted) return;

    // Collect cells for the chosen thread from the pool.
    final cells = fullStitches
        .where((s) => s.threadId == thread!.dmcCode)
        .map<(int, int)>((s) => (s.x, s.y))
        .toList();

    if (cells.isEmpty) return;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => StitchDemoScreen(
        title: pattern.name,
        cols: pattern.width,
        rows: pattern.height,
        cells: cells,
        threadColor: thread!.color,
        threadName: '${thread.dmcCode} – ${thread.name}',
        aidaColor: pattern.aidaColor,
      ),
    );
  }
}
