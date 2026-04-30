part of 'editor_provider.dart';

// ─── SnippetEditorState ───────────────────────────────────────────────────────

/// Session state for the snippet editor (palette list and active palette index).
class SnippetEditorState {
  final List<SnippetPalette> palettes;
  final int activePaletteIndex;

  const SnippetEditorState({
    this.palettes = const [],
    this.activePaletteIndex = 0,
  });

  SnippetEditorState copyWith({
    List<SnippetPalette>? palettes,
    int? activePaletteIndex,
  }) =>
      SnippetEditorState(
        palettes: palettes ?? this.palettes,
        activePaletteIndex: activePaletteIndex ?? this.activePaletteIndex,
      );
}
