import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/aida_presets.dart';
import '../data/dmc_colors.dart';
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

/// Whether the current platform uses touch as the primary input.
/// On touch platforms keyboard shortcut hints in tooltips are hidden.
bool get _isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// Strip trailing `  [Shortcut]` hint from a tooltip string on touch platforms.
String _tt(String tooltip) {
  if (!_isTouchPlatform) return tooltip;
  return tooltip.replaceFirst(RegExp(r'\s{2,}\[.*?\]\s*$'), '');
}

class EditorToolbar extends ConsumerWidget {
  final bool showSnippetsButton;
  final bool showSaveAsSnippetButton;
  final bool showSpriteSheetButton;
  /// When true, always-visible flip/rotate section for whole-canvas transforms (snippet editor C3).
  final bool showWholeCanvasTransforms;
  final bool showAidaButton;
  /// When non-null, replaces the snippets button with a "Paste from snippet"
  /// button (used inside the snippet editor).
  final VoidCallback? onPasteFromSnippet;
  const EditorToolbar({
    super.key,
    this.showSnippetsButton = true,
    this.showSaveAsSnippetButton = true,
    this.showSpriteSheetButton = true,
    this.showWholeCanvasTransforms = false,
    this.showAidaButton = true,
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
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isPhone = _isTouchPlatform && shortestSide < 600;

    final vDivider = Container(width: 1, height: 32, color: theme.dividerColor);

    // ── Snippet button (shared between tools row and colour row) ──────────
    final snippetButtonWidget = Padding(
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
                  : 'Snippets require .stitches format — Save As to convert',
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
    );

    // ── Scrollable tools row content ──────────────────────────────────────
    // Shared between single-row (tablet/desktop) and top row (phone).
    Widget toolsRowContent() => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // On iPad the toolbar is wide enough that scrolling is never needed.
      // NeverScrollableScrollPhysics removes the horizontal drag recogniser
      // from the gesture arena, preventing it from stealing button taps.
      physics: shortestSide >= 600 ? const NeverScrollableScrollPhysics() : null,
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
                          tooltip: _tt('Draw  [D]'),
                          selected: state.drawingMode == DrawingMode.draw,
                          onTap: () => notifier.setDrawingMode(DrawingMode.draw),
                          builder: (c) => Icon(Icons.draw_outlined, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: _tt('Erase  [E]'),
                          selected: state.drawingMode == DrawingMode.erase,
                          activeColor: theme.colorScheme.error,
                          onTap: () => notifier.setDrawingMode(DrawingMode.erase),
                          builder: (c) => Icon(Icons.auto_fix_normal, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: _tt('Pick colour  [C]'),
                          selected: state.drawingMode == DrawingMode.colorPicker,
                          onTap: () => notifier.setDrawingMode(DrawingMode.colorPicker),
                          builder: (c) => Icon(Icons.colorize_outlined, size: 17, color: c),
                        ),
                        const SizedBox(width: 2),
                        _ToolbarButton(
                          tooltip: _tt('Select  [S]'),
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
                            tooltip: _tt('Full stitch  [1]'),
                            selected: state.currentTool == DrawingTool.fullStitch,
                            onTap: () => notifier.setTool(DrawingTool.fullStitch),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawFullStitch)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Half diagonal /  [2]'),
                            selected: state.currentTool == DrawingTool.halfForward,
                            onTap: () => notifier.setTool(DrawingTool.halfForward),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfForward)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Half diagonal \\  [3]'),
                            selected: state.currentTool == DrawingTool.halfBackward,
                            onTap: () => notifier.setTool(DrawingTool.halfBackward),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfBackward)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Half-cell cross (X in ½ cell)  [4]'),
                            selected: state.currentTool == DrawingTool.halfCross,
                            onTap: () => notifier.setTool(DrawingTool.halfCross),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawHalfCross)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Quarter diagonal (auto-corner)  [5]'),
                            selected: state.currentTool == DrawingTool.quarterDiag,
                            onTap: () => notifier.setTool(DrawingTool.quarterDiag),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawQuarterDiag)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Quarter-cell cross / petit point  [6]'),
                            selected: state.currentTool == DrawingTool.quarterCross,
                            onTap: () => notifier.setTool(DrawingTool.quarterCross),
                            builder: (c) => CustomPaint(
                                painter: _StitchIconPainter(color: c, draw: _drawQuarterCross)),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Backstitch  [7]'),
                            selected: state.currentTool == DrawingTool.backstitch,
                            onTap: () => notifier.setTool(DrawingTool.backstitch),
                            builder: (c) => Icon(Icons.gesture, size: 17, color: c),
                          ),
                          const SizedBox(width: 4),
                          _ToolbarButton(
                            tooltip: _tt('Fill colour  [8]'),
                            selected: state.currentTool == DrawingTool.fill,
                            onTap: () => notifier.setTool(DrawingTool.fill),
                            builder: (c) => Icon(Icons.format_color_fill, size: 17, color: c),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],

                  // Erase sub-options (erase mode only)
                  if (state.drawingMode == DrawingMode.erase) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Size picker — styled like _ToolbarButton, opens a popup menu
                          Tooltip(
                            message: 'Eraser size (${state.eraserSize})',
                            child: _EraserSizeButton(
                              eraserSize: state.eraserSize,
                              selected: !state.fillEraseActive,
                              onSelected: (sz) => notifier.setEraserSize(sz),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Fill erase — in the same radio group as size
                          _ToolbarButton(
                            tooltip: 'Flood Erase (erase connected cells)',
                            selected: state.fillEraseActive,
                            activeColor: const Color(0xFFFF6D00),
                            onTap: () => notifier.toggleFillErase(),
                            builder: (c) => Icon(Icons.format_color_reset, size: 17, color: c),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],

                  // Copy/delete/flip/rotate — shown when in select mode.
                  // Buttons always tappable; look disabled and show a canvas warning when no selection.
                  if (state.drawingMode == DrawingMode.select) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Tooltip(
                        message: state.canvasSelectionMode
                            ? 'Selecting all visible layers'
                            : 'Selecting active layer only',
                        child: IconButton(
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          style: state.canvasSelectionMode
                              ? ButtonStyle(
                                  backgroundColor: WidgetStateProperty.all(
                                      theme.colorScheme.primaryContainer),
                                )
                              : null,
                          icon: Icon(
                            Icons.layers_outlined,
                            color: state.canvasSelectionMode
                                ? theme.colorScheme.onPrimaryContainer
                                : null,
                          ),
                          onPressed: () => notifier.toggleCanvasSelectionMode(),
                        ),
                      ),
                    ),
                    vDivider,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Builder(builder: (context) {
                        final hasRect = state.selectionRect != null;
                        final hasSel = hasRect && state.selectedStitches.isNotEmpty;
                        final disabledColor = theme.disabledColor;
                        final noOverlay = WidgetStateProperty.all(Colors.transparent);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: _tt('Copy  [Cmd+C]'),
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                icon: Icon(Icons.copy_outlined,
                                    color: hasSel ? null : disabledColor),
                                onPressed: hasRect
                                    ? () => notifier.copySelection()
                                    : () => notifier.warnNoSelection(),
                              ),
                            ),
                            if (showSaveAsSnippetButton)
                              Tooltip(
                                message: 'Save as snippet',
                                child: IconButton(
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                  icon: Icon(Icons.bookmark_add_outlined,
                                      color: hasSel ? null : disabledColor),
                                  onPressed: hasRect
                                      ? () => _saveAsSnippet(context, ref)
                                      : () => notifier.warnNoSelection(),
                                ),
                              ),
                            Tooltip(
                              message: _tt('Delete selection  [Del]'),
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: hasSel ? theme.colorScheme.error : disabledColor,
                                ),
                                onPressed: hasRect
                                    ? () => notifier.deleteSelection()
                                    : () => notifier.warnNoSelection(),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    // Flip/rotate — suppressed in snippet editor where the always-visible section handles this.
                    if (!showWholeCanvasTransforms) ...[
                      vDivider,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Builder(builder: (context) {
                          final hasRect = state.selectionRect != null;
                          final hasSel = hasRect && state.selectedStitches.isNotEmpty;
                          final disabledColor = theme.disabledColor;
                          final noOverlay = WidgetStateProperty.all(Colors.transparent);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: _tt('Flip horizontal  [Cmd+Shift+H]'),
                                child: IconButton(
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                  icon: Icon(Icons.flip,
                                      color: hasSel ? null : disabledColor),
                                  onPressed: hasRect
                                      ? () => notifier.flipSelectionH()
                                      : () => notifier.warnNoSelection(),
                                ),
                              ),
                              Tooltip(
                                message: _tt('Flip vertical  [Cmd+Shift+V]'),
                                child: IconButton(
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                  icon: Transform.rotate(
                                    angle: 1.5708,
                                    child: Icon(Icons.flip,
                                        color: hasSel ? null : disabledColor),
                                  ),
                                  onPressed: hasRect
                                      ? () => notifier.flipSelectionV()
                                      : () => notifier.warnNoSelection(),
                                ),
                              ),
                              Tooltip(
                                message: _tt('Rotate 90° CW  [Cmd+Shift+]]'),
                                child: IconButton(
                                  iconSize: 20,
                                  visualDensity: VisualDensity.compact,
                                  style: hasSel ? null : ButtonStyle(overlayColor: noOverlay),
                                  icon: Icon(Icons.rotate_90_degrees_cw_outlined,
                                      color: hasSel ? null : disabledColor),
                                  onPressed: hasRect
                                      ? () => notifier.rotateSelectionCW()
                                      : () => notifier.warnNoSelection(),
                                ),
                              ),
                            ],
                          );
                        }),
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
                            message: _tt('Cancel paste  [Esc]'),
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
                    if (!showWholeCanvasTransforms) ...[
                      vDivider,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: _tt('Flip horizontal  [Cmd+Shift+H]'),
                              child: IconButton(
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.flip),
                                onPressed: () => notifier.flipClipboardH(),
                              ),
                            ),
                            Tooltip(
                              message: _tt('Flip vertical  [Cmd+Shift+V]'),
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
                              message: _tt('Rotate 90° CW  [Cmd+Shift+]]'),
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
                    ],
                    vDivider,
                  ],
                  // Flip/rotate section (snippet editor only) — always
                  // visible; target depends on current mode:
                  //   select + selection  → selection
                  //   paste               → clipboard
                  //   otherwise           → whole canvas
                  if (showWholeCanvasTransforms) ...[
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
                              onPressed: () {
                                if (state.drawingMode == DrawingMode.select &&
                                    state.selectionRect != null) {
                                  notifier.flipSelectionH();
                                } else if (state.drawingMode == DrawingMode.paste) {
                                  notifier.flipClipboardH();
                                } else {
                                  notifier.flipCanvasH();
                                }
                              },
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
                              onPressed: () {
                                if (state.drawingMode == DrawingMode.select &&
                                    state.selectionRect != null) {
                                  notifier.flipSelectionV();
                                } else if (state.drawingMode == DrawingMode.paste) {
                                  notifier.flipClipboardV();
                                } else {
                                  notifier.flipCanvasV();
                                }
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Rotate 90° CW  [Cmd+Shift+]]',
                            child: IconButton(
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                              onPressed: () {
                                if (state.drawingMode == DrawingMode.select &&
                                    state.selectionRect != null) {
                                  notifier.rotateSelectionCW();
                                } else if (state.drawingMode == DrawingMode.paste) {
                                  notifier.rotateClipboardCW();
                                } else {
                                  notifier.rotateCanvasCW();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    vDivider,
                  ],
                  // Sprite sheet button — hidden on phones (shortestSide < 600)
                  if (showSpriteSheetButton &&
                      MediaQuery.of(context).size.shortestSide >= 600)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Tooltip(
                        message: state.isNativeFormat
                            ? 'Import sprite sheet'
                            : 'Sprite sheet import requires .stitches format — Save As to convert',
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
                  // Snippets / paste-from-snippet button (tablet/desktop only;
                  // on phones it moves to the colour row below).
                  if (!isPhone && (showSnippetsButton || onPasteFromSnippet != null))
                    snippetButtonWidget,
                ],
              ),
            ); // end toolsRowContent

    // ── Colour row — tablet/desktop ───────────────────────────────────────
    Widget tabletColourRowContent() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QuickSwatches(state: state),
              _ColorSwatch(state: state),
              vDivider,
              const SizedBox(width: 2),
              Tooltip(
                message: _tt('Undo  [Cmd+Z]'),
                child: IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo),
                  onPressed: state.canUndo ? () => notifier.undo() : null,
                ),
              ),
              Tooltip(
                message: _tt('Redo  [Cmd+Shift+Z]'),
                child: IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.redo),
                  onPressed: state.canRedo ? () => notifier.redo() : null,
                ),
              ),
              if (showAidaButton) ...[
                vDivider,
                const SizedBox(width: 4),
                const _AidaButton(),
                const SizedBox(width: 4),
              ],
            ],
          ),
        );

    // ── Colour row — phone ────────────────────────────────────────────────
    // Snippet icon left-aligned; quick swatches fill the gap (LayoutBuilder
    // limits count to only what fits); selected colour + undo/redo right-aligned.
    Widget phoneColourRowContent() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // Snippet button — left
              if (showSnippetsButton || onPasteFromSnippet != null)
                snippetButtonWidget,
              // Swatches — fill available space, capped to what fits
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const swatchStride = 28.0; // 24px swatch + 4px gap
                    final maxCount =
                        (constraints.maxWidth / swatchStride).floor();
                    return Align(
                      alignment: Alignment.centerRight,
                      child: _QuickSwatches(
                          state: state, maxCount: maxCount.clamp(0, 999)),
                    );
                  },
                ),
              ),
              // Selected colour + undo/redo — right
              _ColorSwatch(state: state),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Undo',
                child: IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo),
                  onPressed: state.canUndo ? () => notifier.undo() : null,
                ),
              ),
              Tooltip(
                message: 'Redo',
                child: IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.redo),
                  onPressed: state.canRedo ? () => notifier.redo() : null,
                ),
              ),
              if (showAidaButton) ...[
                vDivider,
                const SizedBox(width: 4),
                const _AidaButton(),
                const SizedBox(width: 4),
              ],
            ],
          ),
        );

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
      height: isPhone ? null : (_isTouchPlatform ? 60 : 56),
      child: isPhone
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                toolsRowContent(),
                Divider(height: 1, thickness: 1, color: theme.dividerColor),
                phoneColourRowContent(),
              ],
            )
          : Row(
              children: [
                Expanded(child: toolsRowContent()),
                tabletColourRowContent(),
              ],
            ),
    );
  }
}
