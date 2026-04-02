# Editor Screen Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the ~800-line duplication between `editor_screen.dart` and `workspace_screen.dart` by extracting shared widgets and a shared keyboard handler.

**Architecture:** Three extracted units: a shared-widgets file for the three stateless UI components (`EditorMenuRow`, `EditorScreenLockButton`, `EditorImportBanner`), an `EditorCanvasArea` widget for the canvas+FAB+toolbar column layout, and a top-level `handleEditorKeys` utility function for keyboard shortcuts. Both screens become thin orchestrators that use these shared pieces.

**Tech Stack:** Flutter/Dart, flutter_riverpod (ConsumerWidget), no new dependencies.

**User Verification:** NO — no user verification required.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/widgets/editor_shared_widgets.dart` | Create | `EditorMenuRow`, `EditorScreenLockButton`, `EditorImportBanner` |
| `lib/widgets/editor_canvas_area.dart` | Create | `EditorCanvasArea` — canvas + FAB + toolbar column |
| `lib/utils/editor_key_handler.dart` | Create | `handleEditorKeys` — common keyboard shortcut logic |
| `lib/screens/editor_screen.dart` | Modify | Remove duplicate widgets; use shared pieces |
| `lib/screens/workspace_screen_components.dart` | Modify | Remove duplicate widgets; use shared pieces |
| `lib/screens/workspace_screen.dart` | Modify | Use `EditorCanvasArea`; use `handleEditorKeys` |

---

### Task 1: Extract shared small widgets

**Goal:** Create `lib/widgets/editor_shared_widgets.dart` and remove the three duplicated stateless widgets from both screens.

**Files:**
- Create: `lib/widgets/editor_shared_widgets.dart`
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen_components.dart`

**Acceptance Criteria:**
- [ ] `EditorMenuRow`, `EditorScreenLockButton`, `EditorImportBanner` defined once
- [ ] `_MenuRow`, `_ScreenLockButton`, `_WorkspaceScreenLockButton`, `_ImportBanner` removed from both screens
- [ ] `flutter analyze` clean
- [ ] `flutter test` passes

**Verify:** `flutter analyze` → 0 issues; `flutter test` → all pass

**Steps:**

- [ ] **Step 1: Create `lib/widgets/editor_shared_widgets.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

// ─── Shared popup menu row ────────────────────────────────────────────────────

class EditorMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const EditorMenuRow({required this.icon, required this.label, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ─── Screen lock toggle button ────────────────────────────────────────────────

class EditorScreenLockButton extends ConsumerWidget {
  const EditorScreenLockButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keepOn = ref.watch(settingsProvider).keepScreenOn;
    return Tooltip(
      message: keepOn ? 'Screen lock: off' : 'Screen lock: on',
      child: IconButton(
        isSelected: keepOn,
        icon: const Icon(Icons.screen_lock_portrait_outlined),
        selectedIcon: const Icon(Icons.screen_lock_portrait),
        style: keepOn
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              )
            : null,
        onPressed: () =>
            ref.read(settingsProvider.notifier).setKeepScreenOn(!keepOn),
      ),
    );
  }
}

// ─── Import format banner ─────────────────────────────────────────────────────

class EditorImportBanner extends StatelessWidget {
  final String filePath;
  final VoidCallback onSaveAs;
  /// When true, the banner also mentions Drive sync (workspace context).
  final bool showDriveNote;

  const EditorImportBanner({
    required this.filePath,
    required this.onSaveAs,
    this.showDriveNote = false,
    super.key,
  });

  String get _ext {
    final dot = filePath.lastIndexOf('.');
    return dot >= 0 ? filePath.substring(dot + 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final features =
        showDriveNote ? 'snippets and Drive sync' : 'snippets';
    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Imported $_ext file — $features require .stitches format.',
                style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cs.onTertiaryContainer,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSaveAs,
              child: const Text('Save As .stitches',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update `lib/screens/editor_screen.dart`**

Add import near the top:
```dart
import '../widgets/editor_shared_widgets.dart';
```

Replace every usage of `_MenuRow(` with `EditorMenuRow(`, `_ScreenLockButton(ref: ref)` with `const EditorScreenLockButton()`, and `_ImportBanner(` with `EditorImportBanner(`.

Delete the three private class definitions at the bottom of the file (lines 501–596):
- `class _MenuRow extends StatelessWidget { ... }`
- `class _ScreenLockButton extends ConsumerWidget { ... }`
- `class _ImportBanner extends StatelessWidget { ... }`

After replacing usages in `editor_screen.dart`, the file ends at the closing `}` of `EditorScreen` (after `_showResizeDialog`).

- [ ] **Step 3: Update `lib/screens/workspace_screen_components.dart`**

Add import at top (after `part of` directive):
```dart
import '../widgets/editor_shared_widgets.dart';
```

Replace all `_MenuRow(` with `EditorMenuRow(` in `workspace_screen.dart` (the `part of` file can access it via the import in the main file, but it's cleaner to import directly in the components file).

Actually, since `workspace_screen_components.dart` is a `part of` file, imports go in the main file `workspace_screen.dart`. Add to `workspace_screen.dart` imports:
```dart
import '../widgets/editor_shared_widgets.dart';
```

Then replace in `workspace_screen.dart` and `workspace_screen_components.dart`:
- `_MenuRow(` → `EditorMenuRow(`
- `_WorkspaceScreenLockButton()` → `const EditorScreenLockButton()`
- `_ImportBanner(` → `EditorImportBanner(showDriveNote: true,`

Delete from `workspace_screen_components.dart`:
- `class _WorkspaceScreenLockButton extends ConsumerWidget { ... }` (lines 5–30)
- `class _MenuRow extends StatelessWidget { ... }` (lines 119–136)
- `class _ImportBanner extends StatelessWidget { ... }` (lines 264–311)

- [ ] **Step 4: Run analyze and test**

```bash
cd /Users/scottmerchant/dev/Stitches && flutter analyze && flutter test
```
Expected: 0 issues, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/editor_shared_widgets.dart lib/screens/editor_screen.dart lib/screens/workspace_screen_components.dart lib/screens/workspace_screen.dart
git commit -m "refactor: extract EditorMenuRow, EditorScreenLockButton, EditorImportBanner"
```

---

### Task 2: Extract EditorCanvasArea widget

**Goal:** Extract the canvas + FAB + toolbar Column layout into a shared `EditorCanvasArea` widget used by both screens.

**Files:**
- Create: `lib/widgets/editor_canvas_area.dart`
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen.dart`

**Acceptance Criteria:**
- [ ] `EditorCanvasArea` renders import banner (when path provided), canvas, FAB, toolbar
- [ ] FAB stays scoped to canvas area (never overlaps toolbar)
- [ ] Both screens use `EditorCanvasArea` for their editor layout
- [ ] `flutter analyze` clean; `flutter test` passes

**Verify:** `flutter analyze` → 0 issues; `flutter test` → all pass

**Steps:**

- [ ] **Step 1: Create `lib/widgets/editor_canvas_area.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/editor/editor_provider.dart';
import 'editor_shared_widgets.dart';
import 'editor_toolbar.dart';
import 'pattern_canvas.dart';

/// The core editor layout: optional import-format banner → canvas with FAB
/// → bottom toolbar.  Callers are responsible for only rendering this widget
/// when a file is open.
class EditorCanvasArea extends ConsumerWidget {
  /// When non-null, shows the import-format banner with a Save As button.
  final String? importFilePath;
  final VoidCallback? onSaveAs;
  /// Pass true in the Workspace context to mention Drive in the banner text.
  final bool showDriveNoteInBanner;

  const EditorCanvasArea({
    super.key,
    this.importFilePath,
    this.onSaveAs,
    this.showDriveNoteInBanner = false,
  }) : assert(
          importFilePath == null || onSaveAs != null,
          'onSaveAs is required when importFilePath is provided',
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    return Column(
      children: [
        if (importFilePath != null)
          EditorImportBanner(
            filePath: importFilePath!,
            onSaveAs: onSaveAs!,
            showDriveNote: showDriveNoteInBanner,
          ),
        Expanded(
          child: Stack(
            children: [
              const PatternCanvas(),
              Positioned(
                left: 12,
                bottom: 16,
                child: FloatingActionButton.extended(
                  onPressed: () =>
                      ref.read(editorProvider.notifier).toggleStitchMode(),
                  icon: Icon(state.stitchMode
                      ? Icons.edit_outlined
                      : Icons.auto_stories_outlined),
                  label: Text(
                      state.stitchMode ? 'Exit Stitch Mode' : 'Stitch Mode'),
                  backgroundColor: state.stitchMode
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  foregroundColor: state.stitchMode
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SafeArea(top: false, child: EditorToolbar()),
      ],
    );
  }
}
```

- [ ] **Step 2: Update `lib/screens/editor_screen.dart` body**

Add import:
```dart
import '../widgets/editor_canvas_area.dart';
```

In the `build` method, replace the current `Column(children: [if (!state.isNativeFormat) _ImportBanner(...), Expanded(child: Stack([canvas, FAB])), SafeArea(toolbar)])` with:

```dart
Expanded(
  child: Column(
    children: [
      if (!state.isNativeFormat)
        EditorImportBanner(
          filePath: state.filePath!,
          onSaveAs: () => _saveAs(context, ref),
        ),
      Expanded(
        child: Stack(
          children: [
            const PatternCanvas(),
            if (state.isFileOpen)
              Positioned(
                left: 12,
                bottom: 16,
                child: FloatingActionButton.extended(
                  onPressed: () => ref
                      .read(editorProvider.notifier)
                      .toggleStitchMode(),
                  icon: Icon(state.stitchMode
                      ? Icons.edit_outlined
                      : Icons.auto_stories_outlined),
                  label: Text(state.stitchMode
                      ? 'Exit Stitch Mode'
                      : 'Stitch Mode'),
                  backgroundColor: state.stitchMode
                      ? Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                      : null,
                  foregroundColor: state.stitchMode
                      ? Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer
                      : null,
                ),
              ),
          ],
        ),
      ),
      const SafeArea(top: false, child: EditorToolbar()),
    ],
  ),
),
```

Wait — `EditorCanvasArea` already contains the import banner internally, so we can simplify the editor body. Replace the entire expanded editor Column in the body:

```dart
// Before (editor_screen.dart body Column child):
Expanded(
  child: Column(
    children: [
      if (!state.isNativeFormat)
        _ImportBanner(filePath: state.filePath!, onSaveAs: () => _saveAs(context, ref)),
      Expanded(
        child: Stack(children: [
          const PatternCanvas(),
          if (state.isFileOpen)
            Positioned(left: 16, bottom: 16, child: FloatingActionButton.extended(...)),
        ]),
      ),
      const SafeArea(top: false, child: EditorToolbar()),
    ],
  ),
),

// After:
Expanded(
  child: EditorCanvasArea(
    importFilePath: state.isNativeFormat ? null : state.filePath,
    onSaveAs: state.isNativeFormat ? null : () => _saveAs(context, ref),
  ),
),
```

- [ ] **Step 3: Update `lib/screens/workspace_screen.dart` editor branch**

Add import:
```dart
import '../widgets/editor_canvas_area.dart';
```

In the `build` method, find the `editorState.isFileOpen` branch (the `Focus` widget wrapping the `Column`). Replace its `child: Column(...)` body with `EditorCanvasArea`:

```dart
// Before (workspace_screen.dart, inside isFileOpen Focus branch):
child: Column(
  children: [
    if (!editorState.isNativeFormat)
      _ImportBanner(
        filePath: editorState.filePath!,
        onSaveAs: () => _saveAs(context),
      ),
    Expanded(
      child: Stack(children: [
        const PatternCanvas(),
        Positioned(left: 12, bottom: 16,
          child: FloatingActionButton.extended(...)),
      ]),
    ),
    const SafeArea(top: false, child: EditorToolbar()),
  ],
),

// After:
child: EditorCanvasArea(
  importFilePath: editorState.isNativeFormat ? null : editorState.filePath,
  onSaveAs: editorState.isNativeFormat ? null : () => _saveAs(context),
  showDriveNoteInBanner: true,
),
```

- [ ] **Step 4: Run analyze and test**

```bash
cd /Users/scottmerchant/dev/Stitches && flutter analyze && flutter test
```
Expected: 0 issues, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/editor_canvas_area.dart lib/screens/editor_screen.dart lib/screens/workspace_screen.dart
git commit -m "refactor: extract EditorCanvasArea widget"
```

---

### Task 3: Extract and unify keyboard handler

**Goal:** Extract the common keyboard shortcut logic into `lib/utils/editor_key_handler.dart`; use it in both screens; fix missing shortcuts in workspace (flip/rotate, P key) and editor (P key).

**Files:**
- Create: `lib/utils/editor_key_handler.dart`
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen.dart`

**Acceptance Criteria:**
- [ ] Common shortcuts (undo/redo/modes/tools/copy/paste/select-all/delete) handled once
- [ ] Workspace gains flip/rotate selection shortcuts
- [ ] Both screens gain P key for pan (already in workspace, add to editor)
- [ ] Screen-specific hooks (save callback, PDF zoom callback, shortcuts dialog callback) injected via parameters
- [ ] `flutter analyze` clean; `flutter test` passes

**Verify:** `flutter analyze` → 0 issues; `flutter test` → all pass

**Steps:**

- [ ] **Step 1: Create `lib/utils/editor_key_handler.dart`**

```dart
import 'package:flutter/services.dart';
import '../providers/editor/editor_provider.dart';

/// Handles keyboard shortcuts common to both EditorScreen and WorkspaceScreen.
///
/// Call this from each screen's `onKeyEvent` handler. Returns
/// [KeyEventResult.handled] if the key was consumed, [KeyEventResult.ignored]
/// otherwise — allowing the caller to add screen-specific handling after.
///
/// [onSave] — called for Cmd/Ctrl+S. Omit in screens that use auto-save.
/// [onShowShortcuts] — called for Shift+? to display the shortcuts dialog.
/// [onPdfZoomIn] / [onPdfZoomOut] — called for Cmd/Ctrl+= / Cmd/Ctrl+-.
KeyEventResult handleEditorKeys(
  KeyEvent event,
  EditorState state,
  EditorNotifier notifier, {
  VoidCallback? onSave,
  VoidCallback? onShowShortcuts,
  VoidCallback? onPdfZoomIn,
  VoidCallback? onPdfZoomOut,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }

  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight);
  final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
  final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
  final key = event.logicalKey;

  // ── Stitch mode ──────────────────────────────────────────────────────────
  if (state.stitchMode) {
    if (onSave != null && (meta || ctrl) && key == LogicalKeyboardKey.keyS) {
      onSave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      notifier.setDrawingMode(DrawingMode.select);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.space) {
      notifier.setDrawingMode(DrawingMode.pan);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (state.selectionRect != null) {
        notifier.cancelSelection();
      } else {
        notifier.toggleStitchMode();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── PDF zoom shortcuts ────────────────────────────────────────────────────
  if ((meta || ctrl) && onPdfZoomIn != null) {
    if (key == LogicalKeyboardKey.equal) {
      onPdfZoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus && onPdfZoomOut != null) {
      onPdfZoomOut();
      return KeyEventResult.handled;
    }
  }

  // ── Modifier shortcuts ────────────────────────────────────────────────────
  if (meta || ctrl) {
    if (key == LogicalKeyboardKey.keyZ && !shift) {
      notifier.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ && shift) {
      notifier.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      notifier.redo();
      return KeyEventResult.handled;
    }
    if (onSave != null && key == LogicalKeyboardKey.keyS) {
      onSave();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      notifier.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      notifier.copySelection();
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyV) {
      notifier.enterPasteMode();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.keyH) {
      if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
        notifier.flipSelectionH();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.flipClipboardH();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.keyV) {
      if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
        notifier.flipSelectionV();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.flipClipboardV();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.bracketRight) {
      if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
        notifier.rotateSelectionCW();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.rotateClipboardCW();
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.bracketLeft) {
      // Three CW rotations = one CCW rotation.
      if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
        notifier.rotateSelectionCW();
        notifier.rotateSelectionCW();
        notifier.rotateSelectionCW();
      } else if (state.drawingMode == DrawingMode.paste) {
        notifier.rotateClipboardCW();
        notifier.rotateClipboardCW();
        notifier.rotateClipboardCW();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Single-key shortcuts ──────────────────────────────────────────────────
  switch (key) {
    case LogicalKeyboardKey.keyD:
      notifier.setDrawingMode(DrawingMode.draw);
    case LogicalKeyboardKey.keyE:
      notifier.setDrawingMode(DrawingMode.erase);
    case LogicalKeyboardKey.keyP:
      notifier.setDrawingMode(DrawingMode.pan);
    case LogicalKeyboardKey.space:
      notifier.setDrawingMode(DrawingMode.pan);
    case LogicalKeyboardKey.digit1:
      notifier.setTool(DrawingTool.fullStitch);
    case LogicalKeyboardKey.digit2:
      notifier.setTool(DrawingTool.halfForward);
    case LogicalKeyboardKey.digit3:
      notifier.setTool(DrawingTool.halfBackward);
    case LogicalKeyboardKey.digit4:
      notifier.setTool(DrawingTool.halfCross);
    case LogicalKeyboardKey.digit5:
      notifier.setTool(DrawingTool.quarterDiag);
    case LogicalKeyboardKey.digit6:
      notifier.setTool(DrawingTool.quarterCross);
    case LogicalKeyboardKey.digit7:
      notifier.setTool(DrawingTool.backstitch);
    case LogicalKeyboardKey.digit8:
      notifier.setTool(DrawingTool.fill);
    case LogicalKeyboardKey.digit9:
      notifier.setDrawingMode(DrawingMode.erase);
      if (!state.fillEraseActive) notifier.toggleFillErase();
    case LogicalKeyboardKey.keyC:
      notifier.setDrawingMode(DrawingMode.colorPicker);
    case LogicalKeyboardKey.keyS:
      notifier.setDrawingMode(DrawingMode.select);
    case LogicalKeyboardKey.escape:
      notifier.cancelSelection();
    case LogicalKeyboardKey.delete:
    case LogicalKeyboardKey.backspace:
      notifier.deleteSelection();
    case LogicalKeyboardKey.slash:
      if (shift && onShowShortcuts != null) {
        onShowShortcuts();
      } else {
        return KeyEventResult.ignored;
      }
    default:
      return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}
```

- [ ] **Step 2: Update `lib/screens/editor_screen.dart` keyboard handler**

Add import:
```dart
import '../utils/editor_key_handler.dart';
```

Replace the entire `handleKeys` closure in the `build` method with:

```dart
KeyEventResult handleKeys(FocusNode node, KeyEvent event) {
  return handleEditorKeys(
    event,
    state,
    ref.read(editorProvider.notifier),
    onSave: () => _save(context, ref),
  );
}
```

- [ ] **Step 3: Update `lib/screens/workspace_screen.dart` keyboard handler**

Add import:
```dart
import '../utils/editor_key_handler.dart';
```

Replace the entire `handleKeys` closure in the `build` method with:

```dart
KeyEventResult handleKeys(FocusNode node, KeyEvent event) {
  return handleEditorKeys(
    event,
    editorState,
    ref.read(editorProvider.notifier),
    // No onSave — workspace uses auto-save.
    onShowShortcuts: () => showDialog(
      context: context,
      builder: (_) => const _ShortcutsDialog(),
    ),
    onPdfZoomIn: openPdf != null
        ? () => _pdfPanelKey.currentState?.zoomIn()
        : null,
    onPdfZoomOut: openPdf != null
        ? () => _pdfPanelKey.currentState?.zoomOut()
        : null,
  );
}
```

- [ ] **Step 4: Run analyze and test**

```bash
cd /Users/scottmerchant/dev/Stitches && flutter analyze && flutter test
```
Expected: 0 issues, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/editor_key_handler.dart lib/screens/editor_screen.dart lib/screens/workspace_screen.dart
git commit -m "refactor: extract handleEditorKeys and unify keyboard shortcuts"
```
