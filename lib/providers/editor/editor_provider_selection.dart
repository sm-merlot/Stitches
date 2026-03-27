part of 'editor_provider.dart';

// ─── SelectionMixin ───────────────────────────────────────────────────────────
//
// Rubber-band selection, clipboard copy/paste, move/delete selection.

mixin SelectionMixin on Notifier<EditorState> {

  // Abstract declarations for shared helpers defined in EditorNotifier.
  List<CrossStitchPattern> _buildUndoStack();
  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch stitch);
  CrossStitchPattern _patternWithActiveLayerStitches(
      CrossStitchPattern p, List<Stitch> s);
  bool _isInBounds(Stitch s, int maxX, int maxY);
  CrossStitchPattern _pruneUnusedThreads(CrossStitchPattern pattern);
  Thread _resolveThreadSymbol(Thread thread, List<Thread> existingThreads);
  String _serializeClipboard(List<Thread> threads, List<Stitch> stitches);

  // ─── Private helpers ──────────────────────────────────────────────────────

  (List<Thread>, List<Stitch>)? _parseClipboard(String text) {
    try {
      final root = (jsonDecode(text) as Map<String, dynamic>)['stitchx'];
      if (root == null) return null;
      final threads = (root['threads'] as List)
          .map((t) => Thread.fromYaml(t as Map<String, dynamic>))
          .toList();
      final stitches = (root['stitches'] as List)
          .map((s) => Stitch.fromYaml(s as Map<String, dynamic>))
          .toList();
      return (threads, stitches);
    } catch (_) {
      return null;
    }
  }

  // ─── Selection management ─────────────────────────────────────────────────

  void setSelectionRect(Rect? rect) {
    state = state.copyWith(selectionRect: rect);
  }

  void selectAll() {
    state = state.copyWith(
      selectionRect: Rect.fromLTWH(
          0, 0, state.pattern.width.toDouble(), state.pattern.height.toDouble()),
      drawingMode: DrawingMode.select,
      backstitchStartPoint: null,
    );
  }

  Future<void> copySelection() async {
    final rect = state.selectionRect;
    if (rect == null) return;
    final inSel = state.activeLayer.stitches
        .where((s) => EditorState.isStitchInRect(s, rect))
        .toList();
    if (inSel.isEmpty) return;
    final clips = inSel
        .map((s) => EditorState.offsetStitch(s, -rect.left.round(), -rect.top.round()))
        .toList();
    final threadIds = clips.map((s) => s.threadId).toSet();
    final threads =
        state.pattern.threads.where((t) => threadIds.contains(t.dmcCode)).toList();
    await Clipboard.setData(ClipboardData(text: _serializeClipboard(threads, clips)));
    state = state.copyWith(
      clipboard: clips,
      clipboardThreads: threads,
      drawingMode: DrawingMode.paste,
      selectionRect: null,
      clipboardFromSnippet: false,
    );
  }

  /// Reads the system clipboard and enters paste mode if valid stitchx data is found.
  /// Falls back to the in-memory clipboard if the system clipboard has other content.
  Future<void> enterPasteMode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final parsed = _parseClipboard(data!.text!);
      if (parsed != null) {
        final (threads, stitches) = parsed;
        state = state.copyWith(
          clipboard: stitches,
          clipboardThreads: threads,
          drawingMode: DrawingMode.paste,
          selectionRect: null,
        );
        return;
      }
    }
    if (state.clipboard == null || state.clipboard!.isEmpty) return;
    state = state.copyWith(drawingMode: DrawingMode.paste, selectionRect: null);
  }

  /// Stamps the clipboard contents at offset [dx],[dy] from origin (0,0).
  /// Any clipboard threads not yet in the pattern are added automatically.
  void commitPaste(int dx, int dy) {
    final clips = state.clipboard;
    if (clips == null || clips.isEmpty) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;

    var threads = [...state.pattern.threads];
    for (final ct in state.clipboardThreads ?? <Thread>[]) {
      if (!threads.any((t) => t.dmcCode == ct.dmcCode)) {
        threads.add(_resolveThreadSymbol(ct, threads));
      }
    }

    var stitches = [...state.activeLayer.stitches];
    for (final s in clips) {
      final placed = EditorState.offsetStitch(s, dx, dy);
      if (!_isInBounds(placed, maxX, maxY)) continue;
      stitches = _stitchesWithAdded(stitches, placed);
    }
    final newPattern = _patternWithActiveLayerStitches(
        state.pattern.copyWith(threads: threads), stitches);
    state = state.copyWith(
      pattern: newPattern,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void moveSelection(int dx, int dy) {
    final rect = state.selectionRect;
    if (rect == null) return;
    final maxX = state.pattern.width;
    final maxY = state.pattern.height;
    final activeStitches = state.activeLayer.stitches;
    final inSel =
        activeStitches.where((s) => EditorState.isStitchInRect(s, rect)).toList();
    if (inSel.isEmpty) return;
    var remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    for (final s in inSel) {
      final moved = EditorState.offsetStitch(s, dx, dy);
      if (_isInBounds(moved, maxX, maxY)) {
        remaining = _stitchesWithAdded(remaining, moved);
      }
    }
    final newRect = Rect.fromLTWH(
      (rect.left + dx).clamp(0, maxX.toDouble()),
      (rect.top + dy).clamp(0, maxY.toDouble()),
      rect.width,
      rect.height,
    );
    final newPattern = _patternWithActiveLayerStitches(state.pattern, remaining);
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: newRect,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  void deleteSelection() {
    final rect = state.selectionRect;
    if (rect == null) return;
    final activeStitches = state.activeLayer.stitches;
    if (!activeStitches.any((s) => EditorState.isStitchInRect(s, rect))) return;
    final remaining =
        activeStitches.where((s) => !EditorState.isStitchInRect(s, rect)).toList();
    final newPattern = _pruneUnusedThreads(
        _patternWithActiveLayerStitches(state.pattern, remaining));
    state = state.copyWith(
      pattern: newPattern,
      selectionRect: null,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
    );
  }

  /// Escape: if in paste mode, exit back to select; otherwise clear selection rect.
  void cancelSelection() {
    if (state.drawingMode == DrawingMode.paste) {
      state = state.copyWith(drawingMode: DrawingMode.select);
    } else {
      state = state.copyWith(selectionRect: null);
    }
  }
}
