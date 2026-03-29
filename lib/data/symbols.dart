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
  // Playing card suits
  '♠', '♣', '♥', '♦',
  // Arrows
  '↑', '↓', '→', '←', '↗', '↘', '↙', '↖', '↔', '↕',
  // Circled operators
  '⊕', '⊖', '⊗', '⊙', '⊚',
  // More filled / outline shapes
  '▶', '◀', '▸', '◂', '⬡', '⬢', '⬤', '⬥',
  '▪', '▫', '▴', '▾', '◉', '◎',
  // Stars / snowflakes
  '✦', '✧', '✩', '✪', '✫', '✬', '✭', '✮', '✯', '✰',
  // Dingbats / marks
  '✓', '✗', '✚', '✜', '✝',
  // Misc punctuation / currency / special
  '§', '¶', '°', '±', '×', '÷', '€', '£', '¥', '¢',
];
