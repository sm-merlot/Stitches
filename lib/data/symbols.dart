/// Returns true if [symbol] contains at least one visually rendered character.
/// Treats empty strings, whitespace-only strings, and strings made entirely of
/// control characters or Unicode invisible/zero-width codepoints as "no symbol".
bool symbolIsVisible(String symbol) {
  if (symbol.isEmpty) return false;
  for (final rune in symbol.runes) {
    if (_isVisibleRune(rune)) return true;
  }
  return false;
}

bool _isVisibleRune(int rune) {
  if (rune <= 0x20) return false;           // C0 controls + space
  if (rune == 0x7F) return false;           // DEL
  if (rune >= 0x80 && rune <= 0x9F) return false;  // C1 controls
  if (rune == 0x00A0) return false;         // no-break space (NBSP)
  if (rune == 0x00AD) return false;         // soft hyphen
  if (rune == 0x1680) return false;         // Ogham space mark
  if (rune >= 0x2000 && rune <= 0x200A) return false;  // Unicode Zs spaces (en/em/thin/hair…)
  if (rune == 0x200B) return false;         // zero-width space
  if (rune == 0x200C) return false;         // zero-width non-joiner
  if (rune == 0x200D) return false;         // zero-width joiner
  if (rune >= 0x200E && rune <= 0x200F) return false;  // LRM / RLM
  if (rune >= 0x202A && rune <= 0x202E) return false;  // directional formatting
  if (rune == 0x202F) return false;         // narrow no-break space
  if (rune == 0x205F) return false;         // medium mathematical space
  if (rune >= 0x2060 && rune <= 0x2064) return false;  // invisible operators
  if (rune == 0x3000) return false;         // ideographic space
  if (rune == 0xFEFF) return false;         // BOM / zero-width no-break space
  return true;
}

/// Ordered pool of symbols available for thread identification in patterns.
const kPatternSymbols = [
  // Uppercase Latin
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
  'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
  'U', 'V', 'W', 'X', 'Y', 'Z',
  // Digits
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  // ASCII punctuation / operators
  '+', '-', '/', '|', '#', '@', r'$', '%', '&', '~',
  '!', '?', '<', '>', '=', '^', '*',
  // Filled / outline geometric shapes
  '■', '●', '▲', '▼', '◆', '★', '○', '□', '△', '◇',
  // Lowercase Latin (visually distinct from uppercase)
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
  'k', 'm', 'n', 'p', 'q', 'r', 's', 'u', 'v', 'w', 'x', 'y', 'z',
  // Greek (recognisable at small cell sizes)
  'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'λ', 'μ',
  'ξ', 'π', 'ρ', 'σ', 'τ', 'φ', 'χ', 'ψ', 'ω',
  // Playing card suits (outline variants — filled suits have emoji presentation)
  '♤', '♧', '♡', '♢',
  // Circled operators (only ⊙ is covered by NotoSansSymbols2)
  '⊙',
  // More filled / outline shapes
  '▶', '◀', '⬡', '⬢', '⬤', '⬥', '◉', '◎',
  // Stars — kept to visually distinct variants only
  '✦', '✩',
  // Dingbats / marks (✝ U+271D is absent from both bundled fonts — omitted)
  '✓', '✗', '✚', '✜',
  // Misc punctuation / currency / special
  '§', '¶', '°', '±', '×', '÷', '€', '£', '¥', '¢',
];

/// Symbols that are visually valid in the app but absent from the bundled
/// PDF fonts (NotoSans-Regular + NotoSansSymbols2-Regular).
/// Patterns created before these were removed from [kPatternSymbols] may
/// still have them assigned. They must be treated as "no symbol" everywhere
/// a PDF-printable symbol is required.
const kPdfUnsupportedSymbols = <String>{
  // Arrows U+2190–21FF — in neither bundled font
  '↑', '↓', '→', '←', '↗', '↘', '↙', '↖', '↔', '↕',
  // Circled operators not covered by NotoSansSymbols2
  '⊕', '⊖', '⊗', '⊚',
  // U+271D — absent from both fonts
  '✝',
};

/// Returns true when [symbol] cannot be rendered in exported PDFs.
bool symbolIsPdfUnsupported(String symbol) =>
    kPdfUnsupportedSymbols.contains(symbol);

/// Symbols safe for PatternKeeper PDF round-trip export.
///
/// Excludes ASCII letters (A-Z, a-z) and digits (0-9) because those appear in
/// page headers, footers, ruler labels, and column numbers — the parser cannot
/// distinguish them from real grid symbols.  Only non-letter, non-digit
/// codepoints that are also in the bundled PDF fonts are included.
const kPkSafeSymbols = <String>[
  // ASCII punctuation / operators (not appearing in header/footer text)
  '+', '#', '@', r'$', '%', '&', '~', '!', '?', '^', '*',
  // Filled / outline geometric shapes
  '■', '●', '▲', '▼', '◆', '★', '○', '□', '△', '◇',
  // More shapes
  '▶', '◀', '⬡', '⬢', '⬤', '⬥', '◉', '◎',
  // Stars / dingbats
  '✦', '✩', '✓', '✗', '✚', '✜',
  // Playing card suits
  '♤', '♧', '♡', '♢',
  // Circled operator
  '⊙',
  // Greek letters (visually distinct; not in Roman page text)
  'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'λ', 'μ',
  'ξ', 'π', 'ρ', 'σ', 'τ', 'φ', 'χ', 'ψ', 'ω',
  // Misc punctuation / currency / special
  '§', '¶', '°', '±', '×', '÷', '€', '£', '¥', '¢',
];

/// Groups of symbols that are visually similar at small cell sizes.
/// If a pattern uses two symbols from the same group, a warning is shown in
/// the colours panel.
const kSimilarSymbolGroups = [
  // Circles / ovals
  {'O', 'o', '0', '○'},
  // Vertical strokes
  {'I', 'l', '1', '|', 'i'},
  // Filled circles
  {'●', '◉', '⬤'},
  // Diamonds
  {'◆', '◇', '⬥'},
  // Stars
  {'★', '✦', '✩'},
];

/// Returns the similarity group index (0-based) that [symbol] belongs to,
/// or -1 if [symbol] is not in any group.
int symbolSimilarityGroup(String symbol) {
  for (int i = 0; i < kSimilarSymbolGroups.length; i++) {
    if (kSimilarSymbolGroups[i].contains(symbol)) return i;
  }
  return -1;
}
