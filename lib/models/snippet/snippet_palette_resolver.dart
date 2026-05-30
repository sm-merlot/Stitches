import 'package:flutter/material.dart' show Color;

import 'snippet.dart';
import '../thread.dart';

/// Resolves the display [Thread] for [baseThreadId] in [snippet],
/// applying the active palette's colour mapping.
///
/// Slot mapping: palettes[0] defines canonical slot order.
/// palettes[n].threads[i] replaces palettes[0].threads[i] when palette n is active.
///
/// For sprite-imported snippets [baseThreadId] is a slotId (e.g. 'slot:2').
/// For manual snippets it is a DMC code (e.g. '310').
Thread resolveThread(Snippet snippet, String baseThreadId) {
  if (snippet.palettes.isEmpty) {
    return Thread(
      dmcCode: baseThreadId,
      color: const Color(0xFF000000),
      name: baseThreadId,
      symbol: '',
    );
  }

  final primary = snippet.palettes[0];

  // Prefer slotId lookup — handles sprite imports where two slots may share a
  // DMC code.  Fall back to dmcCode lookup for manual (legacy) snippets.
  final baseIndex = primary.threads.indexWhere((t) =>
      (t.slotId != null ? t.slotId == baseThreadId : t.dmcCode == baseThreadId));

  if (baseIndex == -1) {
    return primary.threads.isNotEmpty
        ? primary.threads.first
        : Thread(
            dmcCode: baseThreadId,
            color: const Color(0xFF000000),
            name: baseThreadId,
            symbol: '',
          );
  }

  final activeIdx = snippet.activePaletteIndex;
  if (activeIdx == 0 || activeIdx >= snippet.palettes.length) {
    return primary.threads[baseIndex];
  }

  final activePalette = snippet.palettes[activeIdx];
  if (baseIndex >= activePalette.threads.length) {
    return primary.threads[baseIndex];
  }

  return activePalette.threads[baseIndex];
}
