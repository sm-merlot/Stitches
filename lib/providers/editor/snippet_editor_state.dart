part of 'editor_provider.dart';

// ─── SnippetEditorState ───────────────────────────────────────────────────────

/// Session state for the snippet editor (palette list and active palette index).
class SnippetEditorState {
  final List<SnippetPalette> palettes;
  final int activePaletteIndex;

  /// Source colours from a sprite import, displayed read-only for comparison.
  /// Null for non-sprite-imported snippets.
  final SnippetPalette? sourcePalette;

  const SnippetEditorState({
    this.palettes = const [],
    this.activePaletteIndex = 0,
    this.sourcePalette,
  });

  SnippetEditorState copyWith({
    List<SnippetPalette>? palettes,
    int? activePaletteIndex,
    SnippetPalette? sourcePalette,
    bool clearSourcePalette = false,
  }) =>
      SnippetEditorState(
        palettes: palettes ?? this.palettes,
        activePaletteIndex: activePaletteIndex ?? this.activePaletteIndex,
        sourcePalette: clearSourcePalette ? null : (sourcePalette ?? this.sourcePalette),
      );
}
