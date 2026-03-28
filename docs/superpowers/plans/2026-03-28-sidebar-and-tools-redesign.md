# Editor Sidebar & Tools Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ad-hoc palette modal/drawer/toolbar system with a persistent collapsible right sidebar, add flip/rotate operations, remove pan mode, and clean up stitch mode.

**Architecture:** A new `RightSidebar` widget (collapsible, resizable, context-aware tabs) replaces `LayersPanel` in all editor contexts. The `EditorState` stitch view model is changed from a three-value enum to two independent booleans. Flip/rotate operations are added to `SelectionMixin`/`DrawingMixin` and wired into the toolbar and keyboard shortcuts.

**Tech Stack:** Flutter/Dart, Riverpod, `shared_preferences` (already in project), `lib/providers/editor/editor_provider*.dart` mixin architecture.

**Spec:** `docs/superpowers/specs/2026-03-28-editor-sidebar-and-tools-redesign.md`

---

## File Map

**New files:**
- `lib/widgets/right_sidebar.dart` — collapsible/resizable sidebar shell with tab routing
- `lib/widgets/right_sidebar_colours_panel.dart` — Colours tab (3 variants: design/stitch/snippet)
- `lib/widgets/right_sidebar_palettes_panel.dart` — Palettes tab (snippet editor only)

**Modified files:**
- `lib/providers/editor/editor_provider.dart` — EditorState: replace `StitchViewMode stitchViewMode` with `bool stitchCrossMode` + `bool stitchBackMode`
- `lib/providers/editor/editor_provider_drawing.dart` — `toggleStitchMode` enters select (not pan), add `setStitchCrossMode`, `setStitchBackMode`, `flipCanvasH/V`, `rotateCanvasCW`
- `lib/providers/editor/editor_provider_selection.dart` — add `flipSelectionH/V`, `rotateSelectionCW`, `flipClipboardH/V`, `rotateClipboardCW`
- `lib/widgets/canvas_painter.dart` — update `_resolveStitchColor` for new booleans
- `lib/widgets/canvas_painter_overlay.dart` — remove active-layer chip (`_drawActiveLayerChip`)
- `lib/widgets/editor_toolbar.dart` — remove pan button; stitch mode returns `SizedBox.shrink`; add flip/rotate buttons to select/paste modes; add `showWholeCanvasTransforms` param
- `lib/widgets/editor_toolbar_stitch_mode.dart` — delete file (content replaced by sidebar)
- `lib/widgets/snippets_panel.dart` — remove flip/rotate row from context menu (C4)
- `lib/screens/editor_screen.dart` — replace `LayersPanel` → `RightSidebar`; remove `endDrawer`; update keyboard shortcuts; fix FAB padding for stitch mode
- `lib/screens/workspace_screen.dart` — replace `LayersPanel` → `RightSidebar`; remove `endDrawer`
- `lib/screens/workspace_screen_components.dart` — remove `_StitchPalettePanel` class
- `lib/screens/snippet_editor_screen.dart` — add `RightSidebar`; remove palette AppBar button; `EditorToolbar(showWholeCanvasTransforms: true)`; D3 dirty-state warning
- `lib/widgets/pattern_canvas.dart` — D1: prevent `_isMovingSelection` in stitch mode

---

## Task 1: State model — replace StitchViewMode with Cross/Back booleans

**Goal:** Swap the three-value `StitchViewMode` enum for two independent toggle booleans, update `copyWith`, and fix `toggleStitchMode` to enter select mode.

**Files:**
- Modify: `lib/providers/editor/editor_provider.dart`
- Modify: `lib/providers/editor/editor_provider_drawing.dart`

**Acceptance Criteria:**
- [ ] `EditorState` has `stitchCrossMode` and `stitchBackMode` booleans (no `stitchViewMode`)
- [ ] `StitchViewMode` enum is deleted
- [ ] `toggleStitchMode()` enters `DrawingMode.select` (not pan)
- [ ] `setStitchCrossMode` and `setStitchBackMode` toggle independently; activating one clears the other
- [ ] `flutter analyze` passes

**Verify:** `flutter analyze` → no issues

**Steps:**

- [ ] **Step 1: Replace `StitchViewMode` enum with new booleans in `editor_provider.dart`**

In `lib/providers/editor/editor_provider.dart`, delete the `StitchViewMode` enum block (lines ~46–53):
```dart
// DELETE THIS:
enum StitchViewMode {
  normal,
  hidden,
  greyed,
}
```

In `EditorState`, replace:
```dart
// REMOVE:
final StitchViewMode stitchViewMode;
```
with:
```dart
final bool stitchCrossMode; // Cross: hides backstitches, normal stitches shown in colour
final bool stitchBackMode;  // Back: greys normal stitches, backstitches shown in colour
```

In `EditorState` constructor, replace:
```dart
// REMOVE:
this.stitchViewMode = StitchViewMode.normal,
```
with:
```dart
this.stitchCrossMode = false,
this.stitchBackMode = false,
```

In `copyWith`, replace:
```dart
// REMOVE:
StitchViewMode? stitchViewMode,
```
with:
```dart
bool? stitchCrossMode,
bool? stitchBackMode,
```

And in the `copyWith` return, replace:
```dart
// REMOVE:
stitchViewMode: stitchViewMode ?? this.stitchViewMode,
```
with:
```dart
stitchCrossMode: stitchCrossMode ?? this.stitchCrossMode,
stitchBackMode: stitchBackMode ?? this.stitchBackMode,
```

- [ ] **Step 2: Fix `toggleStitchMode()` and add setters in `editor_provider_drawing.dart`**

Replace `toggleStitchMode()`:
```dart
void toggleStitchMode() {
  final entering = !state.stitchMode;
  state = state.copyWith(
    stitchMode: entering,
    drawingMode: entering ? DrawingMode.select : DrawingMode.draw,
    selectionRect: null,
    backstitchStartPoint: null,
    showCompositeThreads: entering,
    stitchCrossMode: false,
    stitchBackMode: false,
  );
  if (entering) refreshCompositeCache();
  _autoSaveStitchMode();
}
```

Replace `setStitchViewMode` with two new setters:
```dart
/// Cross: hides backstitches. Activating clears Back.
void setStitchCrossMode(bool active) {
  state = state.copyWith(
    stitchCrossMode: active,
    stitchBackMode: active ? false : state.stitchBackMode,
  );
}

/// Back: greys normal stitches. Activating clears Cross.
void setStitchBackMode(bool active) {
  state = state.copyWith(
    stitchBackMode: active,
    stitchCrossMode: active ? false : state.stitchCrossMode,
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/editor/editor_provider.dart lib/providers/editor/editor_provider_drawing.dart
git commit -m "refactor: replace StitchViewMode enum with stitchCrossMode/stitchBackMode booleans"
```

---

## Task 2: Canvas painter — update colour resolution for new booleans

**Goal:** Update `CanvasStaticPainter._resolveStitchColor` to use the two new booleans instead of `StitchViewMode`.

**Files:**
- Modify: `lib/widgets/canvas_painter.dart`
- Modify: `lib/widgets/canvas_painter_overlay.dart` — remove active-layer chip

**Acceptance Criteria:**
- [ ] Painter compiles with no reference to `StitchViewMode`
- [ ] Cross mode hides backstitches; Back mode greys normal stitches; both off = full colour
- [ ] Focus composes with Cross/Back as specified in the spec composition table
- [ ] Active layer chip is removed from the canvas overlay

**Verify:** `flutter analyze` → no issues; run app and confirm stitch mode rendering.

**Steps:**

- [ ] **Step 1: Update `CanvasStaticPainter` fields and `_resolveStitchColor` in `canvas_painter.dart`**

Replace the two stitch-mode fields:
```dart
// REMOVE:
final StitchViewMode stitchViewMode;
// ADD:
final bool stitchCrossMode;
final bool stitchBackMode;
```

Update constructor:
```dart
// REMOVE:
this.stitchViewMode = StitchViewMode.normal,
// ADD:
this.stitchCrossMode = false,
this.stitchBackMode = false,
```

Replace `_resolveStitchColor`:
```dart
Color? _resolveStitchColor(String threadId, Color original,
    {required bool isCrossStitch}) {
  if (!stitchMode) return original;

  final hasFocus = stitchFocusThreadId != null;
  final isFocused = !hasFocus || stitchFocusThreadId == threadId;

  // Focus: unfocused stitches always grey
  if (hasFocus && !isFocused) return _greyColor(original);

  // Back mode: grey normal stitches (isCrossStitch here means non-backstitch)
  if (stitchBackMode && isCrossStitch) return _greyColor(original);

  // Cross mode: hide backstitches
  if (stitchCrossMode && !isCrossStitch) return null;

  return original;
}
```

Update `shouldRepaint` — replace:
```dart
// REMOVE:
old.stitchViewMode != stitchViewMode ||
// ADD:
old.stitchCrossMode != stitchCrossMode ||
old.stitchBackMode != stitchBackMode ||
```

- [ ] **Step 2: Update `pattern_canvas.dart` to pass new fields to painter**

Find where `CanvasStaticPainter` is constructed (around line 933) and replace:
```dart
// REMOVE:
stitchViewMode: state.stitchViewMode,
// ADD:
stitchCrossMode: state.stitchCrossMode,
stitchBackMode: state.stitchBackMode,
```

- [ ] **Step 3: Remove active-layer chip from `canvas_painter_overlay.dart`**

In `canvas_painter_overlay.dart`, delete the `activeLayerName` field, its constructor parameter, and the call to `_drawActiveLayerChip` (and the method itself):

```dart
// DELETE these lines:
final String? activeLayerName;           // field
this.activeLayerName,                    // constructor param
if (!stitchMode && activeLayerName != null) {
  _drawActiveLayerChip(canvas, size, activeLayerName!);
}
void _drawActiveLayerChip(Canvas canvas, Size size, String layerName) { ... }
old.activeLayerName != activeLayerName || // shouldRepaint line
```

- [ ] **Step 4: Remove `activeLayerName` from `pattern_canvas.dart`**

Find the `CanvasOverlayPainter` construction (around line 933) and remove:
```dart
// REMOVE:
activeLayerName: state.activeLayer.name,
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/canvas_painter.dart lib/widgets/canvas_painter_overlay.dart lib/widgets/pattern_canvas.dart
git commit -m "refactor: update canvas painter for Cross/Back booleans, remove active-layer chip"
```

---

## Task 3: Provider — flip/rotate operations

**Goal:** Add flip/rotate methods for (a) selection, (b) clipboard, and (c) whole-canvas transforms. Reuse the transform helpers already in `editor_provider_snippets.dart`.

**Files:**
- Modify: `lib/providers/editor/editor_provider_selection.dart`
- Modify: `lib/providers/editor/editor_provider_drawing.dart`

**Acceptance Criteria:**
- [ ] `flipSelectionH/V()` and `rotateSelectionCW()` transform active layer stitches within selection bounds and push to undo stack
- [ ] Selection rect updates correctly after rotate (width ↔ height swap)
- [ ] `flipClipboardH/V()` and `rotateClipboardCW()` transform in-memory clipboard (no undo needed)
- [ ] `flipCanvasH/V()` and `rotateCanvasCW()` transform all layers and push to undo stack (snippet editor whole-canvas)

**Verify:** `flutter analyze` → no issues

**Steps:**

- [ ] **Step 1: Add private transform helpers to `editor_provider_selection.dart`**

These mirror the logic in `transformSnippet()` (in `editor_provider_snippets.dart`) but operate within a selection rect instead of the full canvas. Add these private helpers inside `SelectionMixin`:

```dart
// ─── Selection transform helpers ──────────────────────────────────────────

/// Returns a stitch horizontally flipped within a [W×H] bounding box.
static Stitch _flipStitchH(Stitch s, int l, int t, int w) => switch (s) {
  FullStitch(:final x, :final y, :final threadId) =>
    FullStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId),
  HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
    HalfStitch(x: (l + w - 1) - (x - l), y: y, isForward: !isForward, threadId: threadId),
  QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
    QuarterStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
      quadrant: switch (quadrant) {
        QuadrantPosition.topLeft => QuadrantPosition.topRight,
        QuadrantPosition.topRight => QuadrantPosition.topLeft,
        QuadrantPosition.bottomLeft => QuadrantPosition.bottomRight,
        QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
      }),
  HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
    HalfCrossStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
      half: switch (half) {
        HalfOrientation.left => HalfOrientation.right,
        HalfOrientation.right => HalfOrientation.left,
        HalfOrientation.top => HalfOrientation.top,
        HalfOrientation.bottom => HalfOrientation.bottom,
      }),
  QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
    QuarterCrossStitch(x: (l + w - 1) - (x - l), y: y, threadId: threadId,
      quadrant: switch (quadrant) {
        QuadrantPosition.topLeft => QuadrantPosition.topRight,
        QuadrantPosition.topRight => QuadrantPosition.topLeft,
        QuadrantPosition.bottomLeft => QuadrantPosition.bottomRight,
        QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
      }),
  BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
    BackStitch(
      x1: (l + w) - (x1 - l), y1: y1,
      x2: (l + w) - (x2 - l), y2: y2,
      threadId: threadId),
  _ => s,
};

/// Returns a stitch vertically flipped within a [W×H] bounding box.
static Stitch _flipStitchV(Stitch s, int l, int t, int h) => switch (s) {
  FullStitch(:final x, :final y, :final threadId) =>
    FullStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId),
  HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
    HalfStitch(x: x, y: (t + h - 1) - (y - t), isForward: !isForward, threadId: threadId),
  QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
    QuarterStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
      quadrant: switch (quadrant) {
        QuadrantPosition.topLeft => QuadrantPosition.bottomLeft,
        QuadrantPosition.topRight => QuadrantPosition.bottomRight,
        QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
        QuadrantPosition.bottomRight => QuadrantPosition.topRight,
      }),
  HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
    HalfCrossStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
      half: switch (half) {
        HalfOrientation.left => HalfOrientation.left,
        HalfOrientation.right => HalfOrientation.right,
        HalfOrientation.top => HalfOrientation.bottom,
        HalfOrientation.bottom => HalfOrientation.top,
      }),
  QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
    QuarterCrossStitch(x: x, y: (t + h - 1) - (y - t), threadId: threadId,
      quadrant: switch (quadrant) {
        QuadrantPosition.topLeft => QuadrantPosition.bottomLeft,
        QuadrantPosition.topRight => QuadrantPosition.bottomRight,
        QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
        QuadrantPosition.bottomRight => QuadrantPosition.topRight,
      }),
  BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
    BackStitch(
      x1: x1, y1: (t + h) - (y1 - t),
      x2: x2, y2: (t + h) - (y2 - t),
      threadId: threadId),
  _ => s,
};

/// Returns a stitch rotated 90° CW within selection (L,T,W,H).
/// New grid is H wide × W tall; anchored at same top-left.
static Stitch _rotateStitchCW(Stitch s, int l, int t, int w, int h) {
  // Relative coords: (sx, sy) → rotated (H-1-sy, sx)
  // Absolute: newX = l + (h-1-(y-t)), newY = t + (x-l)
  int rx(int x, int y) => l + (h - 1 - (y - t));
  int ry(int x, int y) => t + (x - l);
  // For float backstitch coords: newX = l + (h-(y-t)), newY = t + (x-l)
  double rbsX(double x, double y) => l + (h - (y - t));
  double rbsY(double x, double y) => t + (x - l);

  return switch (s) {
    FullStitch(:final x, :final y, :final threadId) =>
      FullStitch(x: rx(x, y), y: ry(x, y), threadId: threadId),
    HalfStitch(:final x, :final y, :final isForward, :final threadId) =>
      HalfStitch(x: rx(x, y), y: ry(x, y), isForward: !isForward, threadId: threadId),
    QuarterStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.topRight,
          QuadrantPosition.topRight => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
        }),
    HalfCrossStitch(:final x, :final y, :final half, :final threadId) =>
      HalfCrossStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
        half: switch (half) {
          HalfOrientation.top => HalfOrientation.right,
          HalfOrientation.right => HalfOrientation.bottom,
          HalfOrientation.bottom => HalfOrientation.left,
          HalfOrientation.left => HalfOrientation.top,
        }),
    QuarterCrossStitch(:final x, :final y, :final quadrant, :final threadId) =>
      QuarterCrossStitch(x: rx(x, y), y: ry(x, y), threadId: threadId,
        quadrant: switch (quadrant) {
          QuadrantPosition.topLeft => QuadrantPosition.topRight,
          QuadrantPosition.topRight => QuadrantPosition.bottomRight,
          QuadrantPosition.bottomRight => QuadrantPosition.bottomLeft,
          QuadrantPosition.bottomLeft => QuadrantPosition.topLeft,
        }),
    BackStitch(:final x1, :final y1, :final x2, :final y2, :final threadId) =>
      BackStitch(
        x1: rbsX(x1, y1), y1: rbsY(x1, y1),
        x2: rbsX(x2, y2), y2: rbsY(x2, y2),
        threadId: threadId),
    _ => s,
  };
}
```

- [ ] **Step 2: Add selection flip/rotate public methods to `SelectionMixin`**

```dart
void flipSelectionH() {
  final rect = state.selectionRect;
  if (rect == null) return;
  final l = rect.left.floor();
  final t = rect.top.floor();
  final w = rect.width.round();
  final inSel = (Stitch s) => EditorState.isStitchInRect(s, rect);
  final newStitches = state.activeLayer.stitches.map((s) =>
    inSel(s) ? _flipStitchH(s, l, t, w) : s).toList();
  state = state.copyWith(
    pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
    undoStack: _buildUndoStack(),
  );
}

void flipSelectionV() {
  final rect = state.selectionRect;
  if (rect == null) return;
  final l = rect.left.floor();
  final t = rect.top.floor();
  final h = rect.height.round();
  final inSel = (Stitch s) => EditorState.isStitchInRect(s, rect);
  final newStitches = state.activeLayer.stitches.map((s) =>
    inSel(s) ? _flipStitchV(s, l, t, h) : s).toList();
  state = state.copyWith(
    pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
    undoStack: _buildUndoStack(),
  );
}

void rotateSelectionCW() {
  final rect = state.selectionRect;
  if (rect == null) return;
  final l = rect.left.floor();
  final t = rect.top.floor();
  final w = rect.width.round();
  final h = rect.height.round();
  final inSel = (Stitch s) => EditorState.isStitchInRect(s, rect);
  final newStitches = state.activeLayer.stitches.map((s) =>
    inSel(s) ? _rotateStitchCW(s, l, t, w, h) : s).toList();
  // After CW rotation the selection occupies same top-left but w↔h swap
  final newRect = Rect.fromLTWH(rect.left, rect.top, rect.height, rect.width);
  state = state.copyWith(
    pattern: _patternWithActiveLayerStitches(state.pattern, newStitches),
    selectionRect: newRect,
    undoStack: _buildUndoStack(),
  );
}
```

- [ ] **Step 3: Add clipboard flip/rotate methods to `SelectionMixin`**

Clipboard transforms work on `state.clipboard` list directly (no undo; only the eventual stamp is undoable).

```dart
void flipClipboardH() {
  final clips = state.clipboard;
  if (clips == null || clips.isEmpty) return;
  final w = clips.fold(0, (m, s) {
    final c = EditorState.cellCoords(s);
    return c != null ? (c.$1 + 1 > m ? c.$1 + 1 : m) : m;
  });
  final flipped = clips.map((s) => _flipStitchH(s, 0, 0, w)).toList();
  state = state.copyWith(clipboard: flipped);
}

void flipClipboardV() {
  final clips = state.clipboard;
  if (clips == null || clips.isEmpty) return;
  final h = clips.fold(0, (m, s) {
    final c = EditorState.cellCoords(s);
    return c != null ? (c.$2 + 1 > m ? c.$2 + 1 : m) : m;
  });
  final flipped = clips.map((s) => _flipStitchV(s, 0, 0, h)).toList();
  state = state.copyWith(clipboard: flipped);
}

void rotateClipboardCW() {
  final clips = state.clipboard;
  if (clips == null || clips.isEmpty) return;
  int w = 0, h = 0;
  for (final s in clips) {
    final c = EditorState.cellCoords(s);
    if (c != null) {
      if (c.$1 + 1 > w) w = c.$1 + 1;
      if (c.$2 + 1 > h) h = c.$2 + 1;
    }
  }
  final rotated = clips.map((s) => _rotateStitchCW(s, 0, 0, w, h)).toList();
  state = state.copyWith(clipboard: rotated);
}
```

- [ ] **Step 4: Add whole-canvas flip/rotate to `DrawingMixin` (snippet editor C3)**

```dart
void flipCanvasH() {
  final w = state.pattern.width;
  final newPattern = _patternWithAllLayersTransformed(
    state.pattern,
    (stitches) => stitches.map((s) => SelectionMixin._flipStitchH(s, 0, 0, w)).toList(),
  );
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
  );
}

void flipCanvasV() {
  final h = state.pattern.height;
  final newPattern = _patternWithAllLayersTransformed(
    state.pattern,
    (stitches) => stitches.map((s) => SelectionMixin._flipStitchV(s, 0, 0, h)).toList(),
  );
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
  );
}

void rotateCanvasCW() {
  final w = state.pattern.width;
  final h = state.pattern.height;
  final newPattern = _patternWithAllLayersTransformed(
    state.pattern,
    (stitches) => stitches.map((s) => SelectionMixin._rotateStitchCW(s, 0, 0, w, h)).toList(),
  ).copyWith(width: h, height: w); // swap canvas dimensions
  state = state.copyWith(
    pattern: newPattern,
    undoStack: _buildUndoStack(),
    isDirty: true,
  );
}
```

Note: The static helpers in `SelectionMixin` need to be accessible from `DrawingMixin`. Since both are in the same library (part files of `editor_provider.dart`), static methods on `SelectionMixin` are accessible. Mark the three transform helpers `static` (they don't use `this`).

- [ ] **Step 5: Commit**

```bash
git add lib/providers/editor/editor_provider_selection.dart lib/providers/editor/editor_provider_drawing.dart
git commit -m "feat: add flip/rotate operations for selection, clipboard, and whole-canvas"
```

---

## Task 4: Pan removal, stitch toolbar removal, FAB fix

**Goal:** Remove the Pan toolbar button from design mode; make stitch mode return an empty toolbar; fix stitch mode FAB padding.

**Files:**
- Modify: `lib/widgets/editor_toolbar.dart`
- Delete: `lib/widgets/editor_toolbar_stitch_mode.dart` (content replaced by sidebar)
- Modify: `lib/screens/editor_screen.dart`

**Acceptance Criteria:**
- [ ] Pan button removed from design mode toolbar
- [ ] Stitch mode returns `SizedBox.shrink()` from `EditorToolbar.build()`
- [ ] `_StitchModeToolbar`, `_DemonstrateButton` classes are deleted (Demo moves to sidebar in Task 9)
- [ ] `_saveAsSnippet` function is kept and works
- [ ] FAB has `bottom: 16` in stitch mode and `bottom: 58` in design mode

**Verify:** Run app, enter stitch mode — no toolbar visible; FAB at correct height.

**Steps:**

- [ ] **Step 1: Update `editor_toolbar.dart` — remove Pan button and stitch mode toolbar**

In `EditorToolbar.build()`, replace:
```dart
// REMOVE THIS BLOCK:
if (state.stitchMode) {
  return const _StitchModeToolbar();
}
```
with:
```dart
if (state.stitchMode) return const SizedBox.shrink();
```

In the cursor modes row, remove the Pan button and its `SizedBox(width: 2)` spacer:
```dart
// REMOVE:
const SizedBox(width: 2),
_ToolbarButton(
  tooltip: 'Pan  [P or Space]',
  selected: state.drawingMode == DrawingMode.pan,
  onTap: () => notifier.setDrawingMode(DrawingMode.pan),
  builder: (c) => Icon(Icons.pan_tool_outlined, size: 17, color: c),
),
```

Remove the `part` directive and delete the file reference:
```dart
// REMOVE from editor_toolbar.dart:
part 'editor_toolbar_stitch_mode.dart';
```

- [ ] **Step 2: Move `_saveAsSnippet` out of the deleted file**

The function `_saveAsSnippet` is currently in `editor_toolbar_stitch_mode.dart`. Copy it into `editor_toolbar_button.dart` (keeping it in the same library):

```dart
// Add to lib/widgets/editor_toolbar_button.dart:
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
```

- [ ] **Step 3: Delete `editor_toolbar_stitch_mode.dart`**

```bash
rm lib/widgets/editor_toolbar_stitch_mode.dart
```

- [ ] **Step 4: Fix FAB padding in `editor_screen.dart`**

Replace:
```dart
// REMOVE:
Padding(
  padding: const EdgeInsets.only(bottom: 58),
  child: FloatingActionButton.extended(
```
with:
```dart
Padding(
  padding: EdgeInsets.only(bottom: state.stitchMode ? 16 : 58),
  child: FloatingActionButton.extended(
```

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/editor_toolbar.dart lib/widgets/editor_toolbar_button.dart lib/screens/editor_screen.dart
git commit -m "feat: remove pan button and stitch mode toolbar, fix FAB padding"
```

---

## Task 5: Toolbar — flip/rotate buttons (C1, C2, C3)

**Goal:** Add Flip H / Flip V / Rotate CW buttons to select mode, paste mode, and (optionally) snippet editor whole-canvas.

**Files:**
- Modify: `lib/widgets/editor_toolbar.dart`

**Acceptance Criteria:**
- [ ] Flip H, Flip V, Rotate CW appear in the left section when `drawingMode == DrawingMode.select` and `selectionRect != null`
- [ ] Same three buttons appear in the left section when `drawingMode == DrawingMode.paste`
- [ ] `showWholeCanvasTransforms` parameter added to `EditorToolbar` — when true, always-visible flip/rotate section appears
- [ ] All three call the corresponding notifier methods from Task 3

**Verify:** Run app — select a region, confirm flip/rotate buttons appear and work.

**Steps:**

- [ ] **Step 1: Add `showWholeCanvasTransforms` parameter to `EditorToolbar`**

```dart
class EditorToolbar extends ConsumerWidget {
  final bool showSnippetsButton;
  final bool showSaveAsSnippetButton;
  final bool showSpriteSheetButton;
  final bool showWholeCanvasTransforms; // NEW
  final VoidCallback? onPasteFromSnippet;
  const EditorToolbar({
    super.key,
    this.showSnippetsButton = true,
    this.showSaveAsSnippetButton = true,
    this.showSpriteSheetButton = true,
    this.showWholeCanvasTransforms = false, // NEW
    this.onPasteFromSnippet,
  });
```

- [ ] **Step 2: Add flip/rotate buttons to select mode section**

Inside the `if (state.drawingMode == DrawingMode.select)` block, after the existing copy/save/delete row, add the flip/rotate buttons (only shown when a selection exists and has stitches):

```dart
// Add AFTER the existing copy/delete block, still inside the select mode if:
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
              angle: 1.5708, // 90°
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
```

- [ ] **Step 3: Add flip/rotate buttons to paste mode section**

Inside the `if (state.drawingMode == DrawingMode.paste)` block, add after the save/cancel row:

```dart
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
          icon: Transform.rotate(angle: 1.5708, child: const Icon(Icons.flip)),
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
```

- [ ] **Step 4: Add always-visible whole-canvas section when `showWholeCanvasTransforms`**

In the scrollable left section, before the snippets button, add:

```dart
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
            icon: Transform.rotate(angle: 1.5708, child: const Icon(Icons.flip)),
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
```

- [ ] **Step 5: Remove canvas/layer toggle chip from right section**

In the right section of `EditorToolbar.build()`, remove the entire canvas/layer chip block:
```dart
// REMOVE:
if (state.isFileOpen && !state.stitchMode) ...[
  const SizedBox(width: 4),
  if (state.pattern.layers.any((l) => l.visible && l.opacity < 0.99))
    Tooltip(
      message: 'Opacity active — ...',
      child: Icon(Icons.info_outline, ...),
    ),
  const SizedBox(width: 2),
  ChoiceChip(
    label: Text(state.showCompositeThreads ? 'Canvas' : 'Layer', ...),
    ...
  ),
],
```

The Canvas/Layer toggle now lives in the sidebar Colours panel (Task 9).

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/editor_toolbar.dart
git commit -m "feat: add flip/rotate toolbar buttons for select/paste modes and snippet whole-canvas"
```

---

## Task 6: Keyboard shortcuts — flip/rotate + remove P

**Goal:** Add Cmd+Shift+H/V/]/[ shortcuts in both editor screens; remove the P shortcut for pan (Space-hold stays); update the keyboard shortcuts dialog.

**Files:**
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/snippet_editor_screen.dart`

**Acceptance Criteria:**
- [ ] `P` key no longer switches to pan mode in design mode
- [ ] `Cmd+Shift+H/V` flip the selection (or canvas in snippet editor)
- [ ] `Cmd+Shift+]` rotates CW; `Cmd+Shift+[` rotates CCW (3× CW)
- [ ] Space-hold still activates pan (via the existing `LogicalKeyboardKey.space` case)
- [ ] Stitch mode P shortcut also removed

**Verify:** Press P in design mode — no mode change. Cmd+Shift+H with selection — stitches flip.

**Steps:**

- [ ] **Step 1: Update `editor_screen.dart` key handler**

In the `handleKeys` function, in the stitch mode block, remove:
```dart
// REMOVE (stitch mode P shortcut):
if (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.space) {
  notifier.setDrawingMode(DrawingMode.pan);
  return KeyEventResult.handled;
}
```
Replace with just (Space still does pan-hold but is not persistent; we can keep it or remove it since stitch mode is always select):
```dart
// No P shortcut needed in stitch mode — always-select
```

In the modifier shortcuts block (`if (meta || ctrl)`), add before `return KeyEventResult.ignored`:
```dart
if (shift && key == LogicalKeyboardKey.keyH) {
  // In select or paste mode, flip selection/clipboard; otherwise ignored
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.flipSelectionH();
  } else if (state.drawingMode == DrawingMode.paste) {
    notifier.flipClipboardH();
  }
  return KeyEventResult.handled;
}
if (shift && key == LogicalKeyboardKey.keyV && state.drawingMode != DrawingMode.paste) {
  // Note: Cmd+V is paste; Cmd+Shift+V is flip vertical
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.flipSelectionV();
  }
  return KeyEventResult.handled;
}
if (shift && key == LogicalKeyboardKey.keyV && state.drawingMode == DrawingMode.paste) {
  notifier.flipClipboardV();
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
  // CCW = 3× CW
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
```

In the single-key switch, remove:
```dart
// REMOVE:
case LogicalKeyboardKey.keyP:
  notifier.setDrawingMode(DrawingMode.pan);
```
Keep `LogicalKeyboardKey.space` if you want Space-tap to activate pan transiently, or remove it too. Per spec, pan mode button is gone but Space-hold still works — the pan mode is activated while Space is held and restored when released. This logic is handled elsewhere (in `pattern_canvas.dart`'s Space-hold detection). Remove the P case but keep Space if it's needed for keydown-only handling:
```dart
// Remove the P case; keep Space (it triggers pan mode on hold via canvas)
```

- [ ] **Step 2: Update `snippet_editor_screen.dart` key handler**

In `_handleKeys`, in the `switch (key)` block, remove:
```dart
// REMOVE:
case LogicalKeyboardKey.keyP:
case LogicalKeyboardKey.space:
  notifier.setDrawingMode(DrawingMode.pan);
```

In the modifier shortcuts block, add (before the final `}` of the `if (meta || ctrl)` block):
```dart
if (shift && key == LogicalKeyboardKey.keyH) {
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.flipSelectionH();
  } else if (state.drawingMode == DrawingMode.paste) {
    notifier.flipClipboardH();
  } else {
    notifier.flipCanvasH(); // whole-canvas in snippet editor
  }
  return KeyEventResult.handled;
}
if (shift && key == LogicalKeyboardKey.keyV) {
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.flipSelectionV();
  } else if (state.drawingMode == DrawingMode.paste) {
    notifier.flipClipboardV();
  } else {
    notifier.flipCanvasV();
  }
  return KeyEventResult.handled;
}
if (shift && key == LogicalKeyboardKey.bracketRight) {
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.rotateSelectionCW();
  } else if (state.drawingMode == DrawingMode.paste) {
    notifier.rotateClipboardCW();
  } else {
    notifier.rotateCanvasCW();
  }
  return KeyEventResult.handled;
}
if (shift && key == LogicalKeyboardKey.bracketLeft) {
  if (state.drawingMode == DrawingMode.select && state.selectionRect != null) {
    notifier.rotateSelectionCW(); notifier.rotateSelectionCW(); notifier.rotateSelectionCW();
  } else if (state.drawingMode == DrawingMode.paste) {
    notifier.rotateClipboardCW(); notifier.rotateClipboardCW(); notifier.rotateClipboardCW();
  } else {
    notifier.rotateCanvasCW(); notifier.rotateCanvasCW(); notifier.rotateCanvasCW();
  }
  return KeyEventResult.handled;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/editor_screen.dart lib/screens/snippet_editor_screen.dart
git commit -m "feat: add flip/rotate keyboard shortcuts, remove P pan shortcut"
```

---

## Task 7: SnippetsPanel — remove flip/rotate from context menu (C4)

**Goal:** Remove the flip/rotate `_TransformButton` row from the snippet context menu in `snippets_panel.dart`.

**Files:**
- Modify: `lib/widgets/snippets_panel.dart`

**Acceptance Criteria:**
- [ ] The `Divider` + `Padding` + `Row` of `_TransformButton` widgets are removed from the context menu sheet
- [ ] The `_TransformButton` class in `snippets_panel_widgets.dart` is deleted

**Verify:** Long-press a snippet → menu shows Edit, Manage palettes, Rename, Resize, Delete — no flip/rotate buttons.

**Steps:**

- [ ] **Step 1: Remove flip/rotate section from context menu in `snippets_panel.dart`**

Find and remove the entire block (approximately lines 174–211):
```dart
// REMOVE:
const Divider(height: 1),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Row(
    children: [
      _TransformButton(icon: Icons.flip, label: 'Flip H', onTap: () { ... }),
      const SizedBox(width: 8),
      _TransformButton(icon: Icons.flip, label: 'Flip V', iconFlip: true, onTap: () { ... }),
      const SizedBox(width: 8),
      _TransformButton(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Rotate 90°', onTap: () { ... }),
    ],
  ),
),
```

- [ ] **Step 2: Delete `_TransformButton` from `snippets_panel_widgets.dart`**

Remove the entire `_TransformButton` class from `lib/widgets/snippets_panel_widgets.dart`.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/snippets_panel.dart lib/widgets/snippets_panel_widgets.dart
git commit -m "feat(C4): remove flip/rotate from snippet context menu"
```

---

## Task 8: Right sidebar widget (shell)

**Goal:** Create the collapsible, resizable right sidebar shell with context-aware tab routing.

**Files:**
- Create: `lib/widgets/right_sidebar.dart`

**Acceptance Criteria:**
- [ ] Sidebar collapses to a 40px strip with chevron; expands to full width on tap
- [ ] Width is drag-resizable (min 140, max 350, default 200)
- [ ] Collapsed state persists in `SharedPreferences` key `'sidebar_right_collapsed'`
- [ ] `RightSidebarContext.mainEditor`: shows `Layers` + `Colours` tabs in design mode, `Colours`-only in stitch mode
- [ ] `RightSidebarContext.snippetEditor`: shows `Palettes` + `Colours` tabs always

**Verify:** Run app — collapse sidebar, restart app — sidebar is still collapsed.

**Steps:**

- [ ] **Step 1: Create `lib/widgets/right_sidebar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/editor/editor_provider.dart';
import 'layers_panel.dart';
import 'right_sidebar_colours_panel.dart';
import 'right_sidebar_palettes_panel.dart';

enum RightSidebarContext { mainEditor, snippetEditor }

const _kCollapsedKey = 'sidebar_right_collapsed';
const _kCollapsedWidth = 32.0;
const _kDefaultWidth = 200.0;
const _kMinWidth = 140.0;
const _kMaxWidth = 350.0;

class RightSidebar extends ConsumerStatefulWidget {
  final RightSidebarContext sidebarContext;
  const RightSidebar({super.key, required this.sidebarContext});

  @override
  ConsumerState<RightSidebar> createState() => _RightSidebarState();
}

class _RightSidebarState extends ConsumerState<RightSidebar>
    with SingleTickerProviderStateMixin {
  bool _collapsed = false;
  double _width = _kDefaultWidth;

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _collapsed = prefs.getBool(_kCollapsedKey) ?? false);
    }
  }

  Future<void> _setCollapsed(bool value) async {
    setState(() => _collapsed = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCollapsedKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final theme = Theme.of(context);
    final isStitchMode = state.stitchMode;
    final isSnippet = widget.sidebarContext == RightSidebarContext.snippetEditor;

    if (!state.isFileOpen && !isSnippet) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Resize handle (left edge)
        if (!_collapsed)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _width = (_width - details.delta.dx)
                      .clamp(_kMinWidth, _kMaxWidth);
                });
              },
              child: Container(
                width: 5,
                color: Colors.transparent,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.dividerColor,
                ),
              ),
            ),
          ),
        if (_collapsed)
          // Thin collapsed strip
          Container(
            width: _kCollapsedWidth,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(left: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              children: [
                IconButton(
                  tooltip: 'Expand sidebar',
                  icon: const Icon(Icons.chevron_left, size: 18),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setCollapsed(false),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: _width,
            child: Container(
              color: theme.colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme, isStitchMode, isSnippet),
                  const Divider(height: 1),
                  Expanded(child: _buildContent(isStitchMode, isSnippet)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, bool isStitchMode, bool isSnippet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Row(
        children: [
          if (isStitchMode || (!isSnippet && isStitchMode))
            Text('Colours',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600))
          else if (isSnippet)
            DefaultTabController(
              length: 2,
              child: const TabBar(
                tabs: [Tab(text: 'Palettes'), Tab(text: 'Colours')],
                isScrollable: true,
                tabAlignment: TabAlignment.start,
              ),
            )
          else
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: const TabBar(
                  tabs: [Tab(text: 'Layers'), Tab(text: 'Colours')],
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Collapse sidebar',
            icon: const Icon(Icons.chevron_right, size: 18),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => _setCollapsed(true),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isStitchMode, bool isSnippet) {
    if (isStitchMode) {
      return const ColoursPanel(mode: ColoursPanelMode.stitch);
    }
    if (isSnippet) {
      return const _TabContent(
        tabs: [PalettesPanel(), ColoursPanel(mode: ColoursPanelMode.snippet)],
      );
    }
    // Main editor design mode
    return const _TabContent(
      tabs: [_LayersPanelBody(), ColoursPanel(mode: ColoursPanelMode.design)],
    );
  }
}

/// Thin wrapper to host TabBarView outside the DefaultTabController that lives
/// in the header. Requires an ancestor DefaultTabController.
class _TabContent extends StatelessWidget {
  final List<Widget> tabs;
  const _TabContent({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return TabBarView(children: tabs);
  }
}

/// Strips the resize-handle chrome from LayersPanel — just the panel body.
class _LayersPanelBody extends ConsumerWidget {
  const _LayersPanelBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuse LayersPanel internals. Since LayersPanel wraps itself in a Row
    // with a resize handle, we call a refactored inner body widget instead.
    // (See Task 8 note: LayersPanel is refactored to expose _LayersPanelBody.)
    return const LayersPanelBody();
  }
}
```

**Implementation note:** `DefaultTabController` in the header and `TabBarView` in the content need to share the same controller. The cleanest way is to lift `DefaultTabController` to wrap both header and content. Restructure `_buildHeader`/`_buildContent` to use a single `DefaultTabController` at the `_RightSidebarState.build` level:

```dart
// In build(), instead of splitting header/content separately:
if (isStitchMode) {
  return _buildStitchLayout(theme);
}
return DefaultTabController(
  length: 2,
  child: _buildTabbedLayout(theme, isSnippet),
);
```

Create `_buildTabbedLayout` that returns a `Column` with a `TabBar` header row (with collapse button) and a `TabBarView` body.

- [ ] **Step 2: Refactor `LayersPanel` to expose an inner `LayersPanelBody` widget**

In `lib/widgets/layers_panel.dart`, extract everything inside the `SizedBox(width: _width)` container into a new public widget `LayersPanelBody`. The outer `LayersPanel` becomes a wrapper that adds the resize handle and the `SizedBox(width: _width)` around `LayersPanelBody`. This lets the sidebar host `LayersPanelBody` directly without duplicate resize logic.

```dart
/// The inner content of the layers panel (header + list). Used inside RightSidebar.
class LayersPanelBody extends ConsumerWidget {
  const LayersPanelBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [same content that was inside the SizedBox in _LayersPanelState.build]
    ...
  }
}
```

The `LayersPanel` widget stays as-is for standalone use but now renders `LayersPanelBody` in its inner column.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/right_sidebar.dart lib/widgets/layers_panel.dart
git commit -m "feat: add RightSidebar shell with collapsible/resizable tab system"
```

---

## Task 9: Colours panel widget

**Goal:** Build the `ColoursPanel` widget with three modes: design (Canvas/Layer radio + thread list), stitch (Cross/Back header + Demo + focus list), snippet (simple thread list).

**Files:**
- Create: `lib/widgets/right_sidebar_colours_panel.dart`

**Acceptance Criteria:**
- [ ] Design mode: Canvas/Layer radio buttons control `showCompositeThreads`; thread list tap sets active draw colour
- [ ] Stitch mode: Cross/Back toggle buttons work as exclusive radio-that-can-be-off; Demo button launches `StitchDemoScreen`; thread tap toggles focus
- [ ] Snippet mode: thread list from active palette; tap sets active draw colour
- [ ] Cross/Back buttons show correct active state from `state.stitchCrossMode` / `state.stitchBackMode`

**Verify:** Run app in stitch mode — tap Cross, backstitches disappear; tap Cross again, they return; tap Back, stitches grey. Tap a thread row — only that thread shows in colour.

**Steps:**

- [ ] **Step 1: Create `lib/widgets/right_sidebar_colours_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/dmc_colors.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/stitch_demo_screen.dart';

enum ColoursPanelMode { design, stitch, snippet }

class ColoursPanel extends ConsumerWidget {
  final ColoursPanelMode mode;
  const ColoursPanel({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (mode) {
      ColoursPanelMode.design  => const _DesignColoursPanel(),
      ColoursPanelMode.stitch  => const _StitchColoursPanel(),
      ColoursPanelMode.snippet => const _SnippetColoursPanel(),
    };
  }
}

// ─── Design mode ──────────────────────────────────────────────────────────────

class _DesignColoursPanel extends ConsumerWidget {
  const _DesignColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final theme = Theme.of(context);

    // Thread list: active layer OR composite canvas
    final threads = state.showCompositeThreads
        ? _compositeThreads(state)
        : state.activeLayer.stitches
            .map((s) => s.threadId).toSet()
            .map((id) => state.pattern.threads.firstWhere(
                (t) => t.dmcCode == id,
                orElse: () => state.pattern.threads.first))
            .where((t) => true)
            .toList();

    final activeLayer = state.pattern.layers.firstWhere(
        (l) => l.id == state.activeLayerId,
        orElse: () => state.pattern.layers.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Canvas / Layer X radio buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              if (state.pattern.layers.any((l) => l.visible && l.opacity < 0.99))
                Tooltip(
                  message: 'Opacity active — Canvas shows resulting blended colours.',
                  child: Icon(Icons.info_outline, size: 14,
                      color: theme.colorScheme.primary),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: true, label: Text('Canvas')),
                    ButtonSegment(
                      value: false,
                      label: Text(activeLayer.name,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  selected: {state.showCompositeThreads},
                  onSelectionChanged: (s) {
                    notifier.setShowCompositeThreads(s.first);
                    if (s.first) notifier.refreshCompositeCache();
                  },
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ThreadList(
            threads: threads,
            selectedThreadId: state.selectedThreadId,
            useDmc: useDmc,
            onTap: (t) => notifier.setSelectedThread(t.dmcCode),
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    if (state.compositeThreadCache != null &&
        state.compositeThreadCache!.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in state.compositeThreadCache!.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
  }
}

// ─── Stitch mode ──────────────────────────────────────────────────────────────

class _StitchColoursPanel extends ConsumerWidget {
  const _StitchColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;
    final theme = Theme.of(context);

    final threads = _compositeThreads(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Stitch Focus header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Bordered "Stitch Focus:" group
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Text('Stitch Focus:',
                          style: TextStyle(fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                      const SizedBox(width: 8),
                      _FocusToggle(
                        label: 'Cross',
                        icon: Icons.close, // filled ✕
                        active: state.stitchCrossMode,
                        onTap: () => notifier.setStitchCrossMode(!state.stitchCrossMode),
                        theme: theme,
                      ),
                      const SizedBox(width: 4),
                      _FocusToggle(
                        label: 'Back',
                        icon: Icons.show_chart, // diagonal stroke
                        active: state.stitchBackMode,
                        onTap: () => notifier.setStitchBackMode(!state.stitchBackMode),
                        theme: theme,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Demo button (outside border)
              _DemoButton(state: state),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Thread list with focus ───────────────────────────────────────────
        Expanded(
          child: _ThreadList(
            threads: threads,
            selectedThreadId: state.stitchFocusThreadId,
            useDmc: useDmc,
            onTap: (t) => notifier.setStitchFocusThread(
                state.stitchFocusThreadId == t.dmcCode ? null : t.dmcCode),
            focusMode: true,
          ),
        ),
      ],
    );
  }

  List<Thread> _compositeThreads(EditorState state) {
    if (state.compositeThreadCache != null &&
        state.compositeThreadCache!.isNotEmpty) {
      final unique = <String, Thread>{};
      for (final t in state.compositeThreadCache!.values) {
        unique[t.dmcCode] = t;
      }
      return unique.values.toList();
    }
    return state.pattern.threads;
  }
}

class _FocusToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final ThemeData theme;
  const _FocusToggle({required this.label, required this.icon,
      required this.active, required this.onTap, required this.theme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
                color: active ? theme.colorScheme.onPrimaryContainer : null),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontSize: 12,
              color: active ? theme.colorScheme.onPrimaryContainer : null,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}

/// Demo button — launches StitchDemoScreen. Ported from deleted _DemonstrateButton.
class _DemoButton extends StatelessWidget {
  final EditorState state;
  const _DemoButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : state.pattern.stitches;
    final focusId = state.stitchFocusThreadId;
    final hasFullStitches = !state.stitchBackMode &&
        pool.any((s) => s is FullStitch && (focusId == null || s.threadId == focusId));

    return Tooltip(
      message: 'Demonstrate stitching (beta)',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.play_circle_outline, size: 16),
            label: const Text('Demo', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 32),
            ),
            onPressed: hasFullStitches ? () => _onDemonstrate(context) : null,
          ),
          Positioned(
            top: -5, right: -5,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('β',
                    style: TextStyle(color: Colors.white, fontSize: 8,
                        fontWeight: FontWeight.bold, height: 1.3)),
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
    final pool = state.selectionRect != null
        ? state.selectedStitches
        : pattern.stitches;
    final fullStitches = pool.whereType<FullStitch>().toList();

    Thread? thread;
    if (focusId != null) {
      thread = pattern.threadByCode(focusId);
    } else {
      final threadIds = fullStitches.map((s) => s.threadId).toSet();
      final candidates =
          pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
      if (candidates.isEmpty) return;
      if (candidates.length == 1) {
        thread = candidates.first;
      } else {
        if (!context.mounted) return;
        thread = await showDialog<Thread>(
          context: context,
          builder: (_) => ColorSelectDialog(threads: candidates),
        );
        if (thread == null) return;
      }
    }

    if (thread == null || !context.mounted) return;

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

// ─── Snippet mode ─────────────────────────────────────────────────────────────

class _SnippetColoursPanel extends ConsumerWidget {
  const _SnippetColoursPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final useDmc = ref.watch(settingsProvider).useDmc;

    final palettes = state.snippetPalettes;
    final activeIdx = state.snippetActivePaletteIndex;
    final threads = (palettes.isNotEmpty && activeIdx < palettes.length)
        ? palettes[activeIdx].threads
        : state.pattern.threads;

    return _ThreadList(
      threads: threads,
      selectedThreadId: state.selectedThreadId,
      useDmc: useDmc,
      onTap: (t) => notifier.setSelectedThread(t.dmcCode),
    );
  }
}

// ─── Shared thread list ───────────────────────────────────────────────────────

class _ThreadList extends StatelessWidget {
  final List<Thread> threads;
  final String? selectedThreadId;
  final bool useDmc;
  final void Function(Thread) onTap;
  final bool focusMode;

  const _ThreadList({
    required this.threads,
    required this.selectedThreadId,
    required this.useDmc,
    required this.onTap,
    this.focusMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No threads yet.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: threads.length,
      itemBuilder: (_, i) {
        final t = threads[i];
        final isSelected = t.dmcCode == selectedThreadId;
        final code = useDmc
            ? t.dmcCode
            : (dmcColorByCode(t.dmcCode)?.anchorCode ?? t.dmcCode);
        final textColor = t.color.computeLuminance() > 0.35
            ? Colors.black
            : Colors.white;

        return InkWell(
          onTap: () => onTap(t),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                  )
                : const BoxDecoration(
                    border: Border(
                        left: BorderSide(color: Colors.transparent, width: 3))),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Colour swatch with symbol
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: t.color,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: t.symbol.isNotEmpty
                      ? Text(t.symbol,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              height: 1.0))
                      : null,
                ),
                const SizedBox(width: 8),
                // Code + name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      Text(t.name,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

Add the missing import for `ColorSelectDialog`:
```dart
import 'color_select_dialog.dart';
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/right_sidebar_colours_panel.dart
git commit -m "feat: add ColoursPanel widget with design/stitch/snippet variants"
```

---

## Task 10: Palettes panel widget (snippet editor)

**Goal:** Build the `PalettesPanel` widget for the snippet editor's Palettes tab — palette list, colour slot editing, duplicate warnings.

**Files:**
- Create: `lib/widgets/right_sidebar_palettes_panel.dart`

**Acceptance Criteria:**
- [ ] Palette list shows all `state.snippetPalettes`; active palette highlighted with left border
- [ ] Tap to activate a palette; double-tap name to rename inline
- [ ] Delete button disabled when only one palette; opens confirm dialog
- [ ] "Add palette…" button at bottom
- [ ] Each palette row expandable to show colour slots
- [ ] Tapping a slot opens the DMC picker to replace it
- [ ] Duplicate slot (same colour as another slot in the same palette) shows amber warning icon

**Verify:** Add a second palette in snippet editor — it appears in the panel; tap to activate; expand and edit a colour slot.

**Steps:**

- [ ] **Step 1: Create `lib/widgets/right_sidebar_palettes_panel.dart`**

The `PalettesPanel` widget reads from `editorProvider.snippetPalettes` and calls the existing notifier methods in `SnippetsMixin`:
- `setSnippetActivePalette(int index)` — activate
- `renameSnippetPalette(int index, String name)` — rename
- `deleteSnippetPalette(int index)` — delete
- `addSnippetPalette(SnippetPalette palette)` — add (triggers `_AddPaletteDialog`)
- `setSnippetPaletteThreadColor(int paletteIndex, int slotIndex, Thread newThread)` — replace slot colour

Check `editor_provider_snippets.dart` for the exact method names; add any missing methods.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/snippet_palette.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';
import '../screens/snippet_editor_screen_dialogs.dart'; // _AddPaletteDialog, _DmcPickerDialog

class PalettesPanel extends ConsumerWidget {
  const PalettesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final palettes = state.snippetPalettes;
    final activeIdx = state.snippetActivePaletteIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: palettes.length,
            itemBuilder: (_, i) => _PaletteRow(
              palette: palettes[i],
              index: i,
              isActive: i == activeIdx,
              canDelete: palettes.length > 1,
              allPalettes: palettes,
            ),
          ),
        ),
        const Divider(height: 1),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add palette…'),
          onPressed: () => _showAddPalette(context, ref, palettes),
        ),
      ],
    );
  }

  Future<void> _showAddPalette(
      BuildContext context, WidgetRef ref, List<SnippetPalette> existing) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _AddPaletteDialog(
        existingNames: existing.map((p) => p.name).toList(),
      ),
    );
    if (result != null && context.mounted) {
      ref.read(editorProvider.notifier).addSnippetPalette(
            SnippetPalette.create(
              name: result,
              threads: existing.isNotEmpty ? existing[0].threads : [],
            ),
          );
    }
  }
}

class _PaletteRow extends ConsumerStatefulWidget {
  final SnippetPalette palette;
  final int index;
  final bool isActive;
  final bool canDelete;
  final List<SnippetPalette> allPalettes;

  const _PaletteRow({
    required super.key,
    required this.palette,
    required this.index,
    required this.isActive,
    required this.canDelete,
    required this.allPalettes,
  });

  @override
  ConsumerState<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends ConsumerState<_PaletteRow> {
  bool _expanded = false;
  bool _renaming = false;
  late TextEditingController _renameCtrl;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController(text: widget.palette.name);
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(editorProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Palette header row ─────────────────────────────────────────────
        GestureDetector(
          onTap: () => notifier.setSnippetActivePalette(widget.index),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isActive
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
              border: widget.isActive
                  ? const Border(
                      left: BorderSide(
                          color: Colors.blue /* theme.primary */,
                          width: 3))
                  : const Border(
                      left: BorderSide(
                          color: Colors.transparent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                // Expand chevron
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 4),
                // Name (double-tap to rename)
                Expanded(
                  child: _renaming
                      ? TextField(
                          controller: _renameCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitRename(notifier),
                          onEditingComplete: () => _commitRename(notifier),
                        )
                      : GestureDetector(
                          onDoubleTap: () {
                            _renameCtrl.text = widget.palette.name;
                            setState(() => _renaming = true);
                          },
                          child: Text(widget.palette.name,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                ),
                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16,
                      color: widget.canDelete
                          ? theme.colorScheme.error
                          : Colors.grey),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.canDelete
                      ? () => _confirmDelete(context, notifier)
                      : null,
                ),
              ],
            ),
          ),
        ),
        // ── Colour slots (expandable) ──────────────────────────────────────
        if (_expanded)
          ...widget.palette.threads.asMap().entries.map((entry) {
            final slotIdx = entry.key;
            final thread = entry.value;
            final isDuplicate = _isDuplicate(slotIdx, thread);
            return _SlotRow(
              thread: thread,
              slotIndex: slotIdx,
              paletteIndex: widget.index,
              isDuplicate: isDuplicate,
              primaryThread: widget.allPalettes.isNotEmpty
                  ? widget.allPalettes[0].threads[slotIdx]
                  : thread,
            );
          }),
      ],
    );
  }

  void _commitRename(EditorNotifier notifier) {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) notifier.renameSnippetPalette(widget.index, name);
    setState(() => _renaming = false);
  }

  Future<void> _confirmDelete(BuildContext context, EditorNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete palette?'),
        content: Text('Delete "${widget.palette.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(editorProvider.notifier).deleteSnippetPalette(widget.index);
    }
  }

  bool _isDuplicate(int slotIdx, Thread thread) {
    final palette = widget.palette;
    for (int i = 0; i < palette.threads.length; i++) {
      if (i != slotIdx && palette.threads[i].dmcCode == thread.dmcCode) {
        return true;
      }
    }
    return false;
  }
}

class _SlotRow extends ConsumerWidget {
  final Thread thread;
  final int slotIndex;
  final int paletteIndex;
  final bool isDuplicate;
  final Thread primaryThread;

  const _SlotRow({
    required this.thread,
    required this.slotIndex,
    required this.paletteIndex,
    required this.isDuplicate,
    required this.primaryThread,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primarySlotLabel = 'Slot ${_slotLabel(slotIndex)}';

    return InkWell(
      onTap: () => _pickColour(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 8, 4),
        child: Row(
          children: [
            // Colour swatch
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: thread.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${primaryThread.dmcCode} → ${thread.dmcCode}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (isDuplicate)
              Tooltip(
                message: 'Same colour as another slot — '
                    'this slot can\'t be drawn on this palette until '
                    'it\'s given a unique colour.',
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.orange.shade700),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickColour(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Thread>(
      context: context,
      builder: (_) => _DmcPickerDialog(initialThread: thread),
    );
    if (result != null) {
      ref.read(editorProvider.notifier)
          .setSnippetPaletteThreadColor(paletteIndex, slotIndex, result);
    }
  }

  static String _slotLabel(int i) {
    // A, B, C, ... Z, AA, AB ...
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (i < 26) return chars[i];
    return chars[(i ~/ 26) - 1] + chars[i % 26];
  }
}
```

**Note on missing notifier methods:** Check `editor_provider_snippets.dart` for `setSnippetActivePalette`, `renameSnippetPalette`, `deleteSnippetPalette`, `addSnippetPalette`, `setSnippetPaletteThreadColor`. Add any missing ones following the existing mixin pattern.

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/right_sidebar_palettes_panel.dart
git commit -m "feat: add PalettesPanel widget for snippet editor palette management"
```

---

## Task 11: Main editor wiring

**Goal:** Replace `LayersPanel` and `endDrawer` in `EditorScreen` and `WorkspaceScreen` with the new `RightSidebar`.

**Files:**
- Modify: `lib/screens/editor_screen.dart`
- Modify: `lib/screens/workspace_screen.dart`
- Modify: `lib/screens/workspace_screen_components.dart`

**Acceptance Criteria:**
- [ ] `LayersPanel()` replaced by `RightSidebar(sidebarContext: RightSidebarContext.mainEditor)` in both screens
- [ ] `endDrawer` and `endDrawerEnableOpenDragGesture` removed from both screens
- [ ] `_StitchPalettePanel` class deleted from `editor_screen.dart` and `workspace_screen_components.dart`
- [ ] Palette toolbar button in stitch mode (was in stitch mode toolbar) is gone — no replacement needed, drawer gone

**Verify:** Run app — Layers tab shows in design mode, Colours tab shows in stitch mode; no end-drawer button.

**Steps:**

- [ ] **Step 1: Update `editor_screen.dart`**

Add import:
```dart
import '../widgets/right_sidebar.dart';
```

In `build()`, replace:
```dart
const LayersPanel(),
```
with:
```dart
const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
```

Remove:
```dart
endDrawer: const _StitchPalettePanel(),
endDrawerEnableOpenDragGesture: false,
```

Delete the entire `_StitchPalettePanel` class from the file.

- [ ] **Step 2: Update `workspace_screen.dart`**

Add import:
```dart
import '../widgets/right_sidebar.dart';
```

Replace `const LayersPanel(),` with:
```dart
const RightSidebar(sidebarContext: RightSidebarContext.mainEditor),
```

Remove `endDrawer` and `endDrawerEnableOpenDragGesture` lines.

- [ ] **Step 3: Delete `_StitchPalettePanel` from `workspace_screen_components.dart`**

Remove the entire class (it's a `part of workspace_screen.dart`). If the file becomes empty after removal, delete the file and remove the `part` directive from `workspace_screen.dart`.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/editor_screen.dart lib/screens/workspace_screen.dart lib/screens/workspace_screen_components.dart
git commit -m "feat: replace LayersPanel and endDrawer with RightSidebar in main editor screens"
```

---

## Task 12: Snippet editor wiring

**Goal:** Add `RightSidebar` to the snippet editor, remove the palette AppBar button, enable whole-canvas transforms toolbar.

**Files:**
- Modify: `lib/screens/snippet_editor_screen.dart`

**Acceptance Criteria:**
- [ ] Body layout changes from `Column` to `Row(Column(...), RightSidebar(...))`
- [ ] `EditorToolbar(showWholeCanvasTransforms: true)` used in snippet editor
- [ ] AppBar palette button removed
- [ ] `_openPaletteManager` method removed (sidebar replaces it)
- [ ] D3: dirty-state detection and discard warning on close

**Verify:** Open snippet editor — right sidebar shows Palettes and Colours tabs; tap Save — snippet saved correctly.

**Steps:**

- [ ] **Step 1: Update body layout in `_SnippetEditorBodyState.build()`**

Add import:
```dart
import '../widgets/right_sidebar.dart';
```

Change the body from:
```dart
body: Focus(
  autofocus: true,
  onKeyEvent: _handleKeys,
  child: Column(
    children: [
      Expanded(child: PatternCanvas()),
      EditorToolbar(
        showSnippetsButton: false,
        showSaveAsSnippetButton: false,
        showSpriteSheetButton: false,
        onPasteFromSnippet: widget.siblingSnippets.isNotEmpty
            ? () => _showSnippetPicker(context)
            : null,
      ),
    ],
  ),
),
```
to:
```dart
body: Focus(
  autofocus: true,
  onKeyEvent: _handleKeys,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Column(
          children: [
            const Expanded(child: PatternCanvas()),
            EditorToolbar(
              showSnippetsButton: false,
              showSaveAsSnippetButton: false,
              showSpriteSheetButton: false,
              showWholeCanvasTransforms: true,
              onPasteFromSnippet: widget.siblingSnippets.isNotEmpty
                  ? () => _showSnippetPicker(context)
                  : null,
            ),
          ],
        ),
      ),
      const RightSidebar(sidebarContext: RightSidebarContext.snippetEditor),
    ],
  ),
),
```

- [ ] **Step 2: Remove palette button from AppBar**

Remove from `actions`:
```dart
// REMOVE:
IconButton(
  tooltip: 'Manage palettes',
  icon: const Icon(Icons.palette_outlined),
  onPressed: () => _openPaletteManager(context),
),
```

Delete `_openPaletteManager()` method.

- [ ] **Step 3: D3 — dirty state warning**

Add a field to track the initial stitch count (a lightweight proxy for dirtiness):

```dart
late int _initialStitchHash;
```

In `initState` post-frame callback, after loading the pattern:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  // ... existing load logic ...
  await Future.delayed(Duration.zero); // let state settle
  if (mounted) {
    setState(() {
      _initialStitchHash = ref.read(editorProvider).pattern.stitches.length;
    });
  }
});
```

Wrap the Scaffold in a `PopScope`:
```dart
return PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    final currentCount = ref.read(editorProvider).pattern.stitches.length;
    final isDirty = currentCount != _initialStitchHash;
    if (!isDirty) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && context.mounted) Navigator.of(context).pop();
  },
  child: Scaffold( ... ),
);
```

**Note:** Using stitch count as the dirty proxy is imprecise (drawing same count stitches in different positions would miss it). A more robust approach uses `Object.hashAll(pattern.stitches)` or a stitch fingerprint. Prefer `pattern.stitches.fold(0, (h, s) => Object.hash(h, s))` for correctness.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/snippet_editor_screen.dart
git commit -m "feat: add RightSidebar to snippet editor, C3 whole-canvas transforms, D3 dirty warning"
```

---

## Task 13: D1 — Prevent accidental stitch moves in stitch mode

**Goal:** In stitch mode, dragging inside a selection should not move stitches — it should pan the canvas instead.

**Files:**
- Modify: `lib/widgets/pattern_canvas.dart`

**Acceptance Criteria:**
- [ ] In stitch mode, clicking inside a selection does not start `_isMovingSelection = true`
- [ ] Dragging inside selection in stitch mode pans the canvas
- [ ] Tapping (no drag) inside selection in stitch mode still deselects (or keeps selection)

**Verify:** In stitch mode, rubber-band select a region then drag inside it — canvas pans, stitches don't move.

**Steps:**

- [ ] **Step 1: Guard `_isMovingSelection` starts with stitch mode check**

In `pattern_canvas.dart`, find each place where `_isMovingSelection = true` is set (currently around lines 511 and 549 — for mouse and touch). Add a stitch mode guard:

```dart
// Mouse pointer down in select mode (around line 506):
if (mode == DrawingMode.select) {
  final cell = _screenToSelCell(event.localPosition);
  final sel = ref.read(editorProvider).selectionRect;
  final inStitchMode = ref.read(editorProvider).stitchMode;  // NEW
  if (sel != null && _cellInSelRect(cell.dx.toInt(), cell.dy.toInt(), sel)) {
    if (!inStitchMode) {  // NEW GUARD
      setState(() {
        _isMovingSelection = true;
        _moveDragStartCell = cell;
        _moveDelta = Offset.zero;
      });
    }
    // In stitch mode: fall through to pan handling (do nothing here,
    // pan is handled by the regular pan code path)
  } else {
    ref.read(editorProvider.notifier).setSelectionRect(null);
    setState(() {
      _selectionAnchor = cell;
      _isMovingSelection = false;
      _hasDraggedSelection = false;
    });
  }
  return;
}
```

Apply the same `!inStitchMode` guard to the touch equivalent (~line 544).

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/pattern_canvas.dart
git commit -m "fix(D1): prevent accidental stitch moves in stitch mode"
```

---

## Task 14: Missing notifier methods for PalettesPanel

**Goal:** Ensure all methods called by `PalettesPanel` exist in `SnippetsMixin`.

**Files:**
- Modify: `lib/providers/editor/editor_provider_snippets.dart`

**Acceptance Criteria:**
- [ ] `setSnippetActivePalette(int index)` exists
- [ ] `renameSnippetPalette(int index, String name)` exists
- [ ] `deleteSnippetPalette(int index)` exists
- [ ] `addSnippetPalette(SnippetPalette palette)` exists
- [ ] `setSnippetPaletteThreadColor(int paletteIndex, int slotIndex, Thread newThread)` exists

**Verify:** `flutter analyze` → no undefined method errors.

**Steps:**

- [ ] **Step 1: Check existing methods and add any missing ones**

Read `editor_provider_snippets.dart` and compare against the list above. Add any that are missing:

```dart
void setSnippetActivePalette(int index) {
  final palettes = state.snippetPalettes;
  if (index < 0 || index >= palettes.length) return;
  state = state.copyWith(snippetActivePaletteIndex: index);
}

void renameSnippetPalette(int index, String name) {
  final palettes = List<SnippetPalette>.from(state.snippetPalettes);
  if (index < 0 || index >= palettes.length) return;
  palettes[index] = palettes[index].copyWith(name: name);
  state = state.copyWith(snippetPalettes: palettes);
}

void deleteSnippetPalette(int index) {
  final palettes = List<SnippetPalette>.from(state.snippetPalettes);
  if (palettes.length <= 1 || index < 0 || index >= palettes.length) return;
  palettes.removeAt(index);
  final activeIdx = state.snippetActivePaletteIndex;
  state = state.copyWith(
    snippetPalettes: palettes,
    snippetActivePaletteIndex: activeIdx >= palettes.length
        ? palettes.length - 1
        : activeIdx,
  );
}

void addSnippetPalette(SnippetPalette palette) {
  state = state.copyWith(
    snippetPalettes: [...state.snippetPalettes, palette],
  );
}

void setSnippetPaletteThreadColor(
    int paletteIndex, int slotIndex, Thread newThread) {
  final palettes = List<SnippetPalette>.from(state.snippetPalettes);
  if (paletteIndex < 0 || paletteIndex >= palettes.length) return;
  final threads = List<Thread>.from(palettes[paletteIndex].threads);
  if (slotIndex < 0 || slotIndex >= threads.length) return;
  threads[slotIndex] = newThread;
  palettes[paletteIndex] = palettes[paletteIndex].copyWith(threads: threads);
  state = state.copyWith(snippetPalettes: palettes);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/providers/editor/editor_provider_snippets.dart
git commit -m "feat: add missing palette management methods to SnippetsMixin"
```

---

## Task 15: Final integration pass & analyze

**Goal:** Ensure everything compiles cleanly and cross-cutting concerns are resolved.

**Steps:**

- [ ] **Run `flutter analyze`**

```bash
flutter analyze
```

Fix any remaining issues:
- Unused imports (e.g. `LayersPanel` import in editor_screen.dart after replacement)
- Any `StitchViewMode` references that were missed (search `grep -r StitchViewMode lib/`)
- Missing imports in new files
- Any `setStitchViewMode` references elsewhere

- [ ] **Search for lingering `StitchViewMode` and `setStitchViewMode` references**

```bash
grep -r "StitchViewMode\|setStitchViewMode\|stitchViewMode" lib/
```

Fix any found by updating to `stitchCrossMode`/`stitchBackMode`.

- [ ] **Search for `_StitchPalettePanel` references**

```bash
grep -r "_StitchPalettePanel\|openEndDrawer" lib/
```

Remove any remaining references.

- [ ] **Check `import 'layers_panel.dart'` in editor_screen.dart**

If `LayersPanel` is no longer used directly in `editor_screen.dart`, remove its import.

- [ ] **Commit cleanup**

```bash
git add -u
git commit -m "fix: cleanup analyze warnings from sidebar redesign"
```

---

## Verification

1. `flutter analyze` → no issues
2. Run `flutter run -d macos`:
   - Design mode: sidebar shows Layers + Colours tabs; Colours tab has Canvas/Layer radio; tap a thread → sets as active draw colour
   - Stitch mode: toolbar gone; sidebar shows Colours only; Cross/Back toggles work; Demo button launches demo screen
   - Snippet editor: sidebar shows Palettes + Colours tabs; whole-canvas flip/rotate work
   - Flip selection: select region, click Flip H → stitches mirror; undo works
   - Flip paste: copy region, Flip H in paste mode → ghost flips before stamping
   - P key: no longer switches to pan mode
   - Sidebar collapses and state persists across restarts
   - Stitch mode: drag inside selection pans canvas, not moves stitches
   - Snippet editor: make changes, tap back → "Discard changes?" dialog appears
