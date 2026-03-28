import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../data/symbols.dart';
import '../models/thread.dart';
import '../models/storage_location.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';
import '../providers/folder_contents_provider.dart';
import '../providers/google_drive_provider.dart';
import '../screens/color_picker_screen.dart';
import '../services/drive_cache.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../screens/sprite_sheet_screen.dart';
import 'snippets_panel.dart';

part 'editor_toolbar_button.dart';
part 'editor_toolbar_color_controls.dart';
part 'editor_toolbar_palette_dialog.dart';
part 'editor_toolbar_sprite_picker.dart';

class EditorToolbar extends ConsumerWidget {
  final bool showSnippetsButton;
  final bool showSaveAsSnippetButton;
  final bool showSpriteSheetButton;
  /// When true, always-visible flip/rotate section for whole-canvas transforms (snippet editor C3).
  final bool showWholeCanvasTransforms;
  /// When non-null, replaces the snippets button with a "Paste from snippet"
  /// button (used inside the snippet editor).
  final VoidCallback? onPasteFromSnippet;
  const EditorToolbar({
    super.key,
    this.showSnippetsButton = true,
    this.showSaveAsSnippetButton = true,
    this.showSpriteSheetButton = true,
    this.showWholeCanvasTransforms = false,
    this.onPasteFromSnippet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);

    // Stitch mode: toolbar not rendered (controls moved to sidebar)
    if (state.stitchMode) {
      return const SizedBox.shrink();
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
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Fill colour  [8]',
                            selected: state.currentTool == DrawingTool.fill,
                            onTap: () => notifier.setTool(DrawingTool.fill),
                            builder: (c) => Icon(Icons.format_color_fill, size: 17, color: c),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: 'Fill erase  [9]',
                            selected: state.currentTool == DrawingTool.fillErase,
                            onTap: () => notifier.setTool(DrawingTool.fillErase),
                            builder: (c) => Icon(Icons.format_color_reset, size: 17, color: c),
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
                    // Flip/rotate — shown when a selection with stitches is active
                    if (state.selectionRect != null && state.selectedStitches.isNotEmpty) ...[
                      vDivider,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Flip horizontal  [Cmd+Shift+H]',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.flip),
                                onPressed: () => notifier.flipSelectionH(),
                              ),
                            ),
                            Tooltip(
                              message: 'Flip vertical  [Cmd+Shift+V]',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: Transform.rotate(
                                  angle: 1.5708,
                                  child: const Icon(Icons.flip),
                                ),
                                onPressed: () => notifier.flipSelectionV(),
                              ),
                            ),
                            Tooltip(
                              message: 'Rotate 90° CW  [Cmd+Shift+]]',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                                onPressed: () => notifier.rotateSelectionCW(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    vDivider,
                  ],
                  // Cancel + opacity + save-as-snippet — shown while paste preview is active
                  if (state.drawingMode == DrawingMode.paste) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Flip horizontal  [Cmd+Shift+H]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.flip),
                              onPressed: () => notifier.flipClipboardH(),
                            ),
                          ),
                          Tooltip(
                            message: 'Flip vertical  [Cmd+Shift+V]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: Transform.rotate(
                                angle: 1.5708,
                                child: const Icon(Icons.flip),
                              ),
                              onPressed: () => notifier.flipClipboardV(),
                            ),
                          ),
                          Tooltip(
                            message: 'Rotate 90° CW  [Cmd+Shift+]]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                              onPressed: () => notifier.rotateClipboardCW(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],
                  // Whole-canvas flip/rotate (snippet editor only)
                  if (showWholeCanvasTransforms) ...[
                    vDivider,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Canvas:', style: TextStyle(fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Flip canvas horizontal  [Cmd+Shift+H]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.flip),
                              onPressed: () => notifier.flipCanvasH(),
                            ),
                          ),
                          Tooltip(
                            message: 'Flip canvas vertical  [Cmd+Shift+V]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: Transform.rotate(
                                angle: 1.5708,
                                child: const Icon(Icons.flip),
                              ),
                              onPressed: () => notifier.flipCanvasV(),
                            ),
                          ),
                          Tooltip(
                            message: 'Rotate canvas 90° CW  [Cmd+Shift+]]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                              onPressed: () => notifier.rotateCanvasCW(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Sprite sheet button — hidden on phones (shortestSide < 600)
                  if (showSpriteSheetButton &&
                      MediaQuery.of(context).size.shortestSide >= 600)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Tooltip(
                        message: state.isNativeFormat
                            ? 'Import sprite sheet'
                            : 'Sprite sheet import requires .stitchx format — Save As to convert',
                        child: IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          icon: const FaIcon(FontAwesomeIcons.ghost),
                          onPressed: state.isFileOpen && state.isNativeFormat
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
                              message: state.isNativeFormat
                                  ? 'Snippets'
                                  : 'Snippets require .stitchx format — Save As to convert',
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.collections_bookmark_outlined),
                                onPressed: state.isFileOpen && state.isNativeFormat
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
