// Fetches the latest DMC thread color list and updates lib/data/dmc_colors.dart.
//
// Primary source:   cheshire137/cross-stitch-color-conversion (JSON, ~456 colors)
// Supplementary:    KDE/kxstitch schemes/dmc.xml (XML, ~489 colors)
//
// The KXStitch XML is used to fill in colors that the primary JSON source omits.
// Currently this covers DMC 01–35 (released 2017/2018), which the cheshire137
// dataset has never included. If primary has a code, its data wins; if only
// KXStitch has it, KXStitch data is used instead.
//
// What it does:
//   • Adds colors present in either source but missing from the app list.
//   • Removes colors absent from BOTH sources: moves them out of dmcColors and
//     adds placeholder entries (empty replacement) to dmcReplacements so they
//     show up in the PR for review. Fill in the replacement before merging, or
//     revert the change if it turns out to be a false alarm.
//   • Updates name/hex for colors whose details changed in the primary source
//     (KXStitch-only entries are never overwritten by the primary source).
//   • Never overwrites existing Anchor codes; preserves them on updates.
//   • Writes PR body to $RUNNER_TEMP (CI) or tool/.pr_body.md (local); sets GITHUB_OUTPUT.
//
// Usage:
//   dart run tool/update_dmc_colors.dart

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _sourceUrl = 'https://raw.githubusercontent.com/'
    'cheshire137/cross-stitch-color-conversion/'
    'main/src/assets/dmc-color-codes-names.json';

/// Supplementary source: KDE/kxstitch DMC scheme XML.
/// Used only for codes the primary JSON source does not include (e.g. 01–35).
const _supplementaryUrl =
    'https://raw.githubusercontent.com/KDE/kxstitch/master/schemes/dmc.xml';

const _colorsPath = 'lib/data/dmc_colors.dart';
// In CI, write outside the checkout so create-pull-request doesn't commit it.
String get _prBodyPath {
  final runnerTemp = Platform.environment['RUNNER_TEMP'];
  return runnerTemp != null ? '$runnerTemp/.pr_body.md' : 'tool/.pr_body.md';
}

String get _changesetPath {
  final now = DateTime.now();
  final slug =
      'dmc-colors-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return '.changeset/$slug.md';
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _Color implements Comparable<_Color> {
  final String code;
  final String name;
  final String hex; // 6-char uppercase, no '#'
  final String? anchor;

  const _Color(this.code, this.name, this.hex, [this.anchor]);

  @override
  int compareTo(_Color other) {
    final ia = int.tryParse(code);
    final ib = int.tryParse(other.code);
    if (ia == null && ib == null) return code.compareTo(other.code);
    if (ia == null) return -1; // special codes (White, Ecru, B5200) before numeric
    if (ib == null) return 1;
    return ia.compareTo(ib);
  }

  String toDartLine() {
    final anchorPart = anchor != null ? ", '$anchor'" : '';
    return "  DmcColor('$code', '$name', Color(0xFF$hex)$anchorPart),";
  }
}

// ─── HTTP ─────────────────────────────────────────────────────────────────────

Future<String> _get(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} from $url');
    }
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

// ─── Parsing ──────────────────────────────────────────────────────────────────

List<_Color> _parseSource(String json) {
  final list = jsonDecode(json) as List;
  return (list.map((e) {
    final m = e as Map;
    return _Color(
      (m['dmcCode'] as String).trim(),
      (m['dmcName'] as String).trim(),
      (m['hexCode'] as String).trim().replaceFirst('#', '').toUpperCase(),
    );
  }).toList()
    ..sort());
}

/// Parses the KXStitch DMC XML and returns colors as [_Color] objects.
/// Only colors NOT already present in [primaryCodes] are returned, so the
/// primary source always wins when both cover the same code.
List<_Color> _parseSupplementary(String xml, Set<String> primaryCodes) {
  final colors = <_Color>[];
  // Simple regex-based parse — avoids pulling in an xml package.
  final flossRe = RegExp(
    r'<floss>.*?<name>(.*?)</name>.*?<description>(.*?)</description>'
    r'.*?<red>(\d+)</red>.*?<green>(\d+)</green>.*?<blue>(\d+)</blue>.*?</floss>',
    dotAll: true,
  );
  for (final m in flossRe.allMatches(xml)) {
    final code = m.group(1)!.trim();
    if (primaryCodes.contains(code)) continue; // primary source wins
    final name = m.group(2)!.trim();
    final r = int.parse(m.group(3)!);
    final g = int.parse(m.group(4)!);
    final b = int.parse(m.group(5)!);
    final hex = r.toRadixString(16).padLeft(2, '0') +
        g.toRadixString(16).padLeft(2, '0') +
        b.toRadixString(16).padLeft(2, '0');
    colors.add(_Color(code, name, hex.toUpperCase()));
  }
  return colors;
}

final _entryRe = RegExp(
  r"DmcColor\('([^']+)', '([^']+)', Color\(0xFF([0-9A-Fa-f]{6})\)(?:, '([^']+)')?\)",
);

List<_Color> _parseCurrentFile(String content) {
  return _entryRe.allMatches(content).map((m) {
    return _Color(
      m.group(1)!,
      m.group(2)!,
      m.group(3)!.toUpperCase(),
      m.group(4), // anchor — may be null
    );
  }).toList();
}

/// Returns the set of DMC codes already present in the dmcReplacements map.
Set<String> _parseReplacementKeys(String content) {
  const header = 'const Map<String, String> dmcReplacements = {';
  final start = content.indexOf(header);
  if (start == -1) return {};
  final end = content.indexOf('\n};', start + header.length);
  if (end == -1) return {};
  final block = content.substring(start + header.length, end);
  return RegExp(r"'([^']+)':")
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

// ─── Update record ────────────────────────────────────────────────────────────

class _Update {
  final _Color oldColor;
  final _Color newColor;

  const _Update(this.oldColor, this.newColor);

  bool get hexChanged => oldColor.hex != newColor.hex;
  bool get nameChanged => oldColor.name != newColor.name;
}

// ─── PR body ──────────────────────────────────────────────────────────────────

void _writePrBody({
  required List<_Color> added,
  required List<_Color> retired,
  required List<_Update> updated,
}) {
  final buf = StringBuffer();

  final total = added.length + retired.length + updated.length;
  buf.writeln('## DMC Color List Update\n');
  buf.writeln('Automated monthly sync against the '
      '[cheshire137/cross-stitch-color-conversion]'
      '(https://github.com/cheshire137/cross-stitch-color-conversion) dataset, '
      'supplemented by [KDE/kxstitch](https://github.com/KDE/kxstitch) for codes '
      'the primary source omits (e.g. DMC 01–35).\n');

  if (total == 0) {
    buf.writeln('No changes detected.');
  } else {
    final parts = [
      if (added.isNotEmpty) '**${added.length} added**',
      if (retired.isNotEmpty)
        '**${retired.length} possibly retired** (removed from list, replacement TBD)',
      if (updated.isNotEmpty) '**${updated.length} updated**',
    ];
    buf.writeln(parts.join(' · '));
  }

  if (added.isNotEmpty) {
    buf.writeln('\n### ➕ New colors\n');
    buf.writeln(
        '> Add Anchor equivalents manually in `lib/data/dmc_colors.dart` before merging.\n');
    buf.writeln('| DMC | Name | Hex |');
    buf.writeln('|-----|------|-----|');
    for (final c in added) {
      buf.writeln('| ${c.code} | ${c.name} | `#${c.hex}` |');
    }
  }

  if (retired.isNotEmpty) {
    buf.writeln('\n### 🗑️ Possibly retired (removed from dmcColors)\n');
    buf.writeln(
        'These colors were absent from the community source and have been removed '
        'from `dmcColors`. Placeholder entries (empty replacement) have been added '
        'to `dmcReplacements`.\n\n'
        '**Before merging:** fill in each replacement code in `dmcReplacements`, '
        'or revert the entry if the source was wrong.\n');
    buf.writeln('| DMC | Name | Hex | Current Anchor |');
    buf.writeln('|-----|------|-----|----------------|');
    for (final c in retired) {
      buf.writeln('| ${c.code} | ${c.name} | `#${c.hex}` | ${c.anchor ?? '—'} |');
    }
  }

  if (updated.isNotEmpty) {
    final hexAndName = updated.where((u) => u.hexChanged && u.nameChanged).toList();
    final hexOnly = updated.where((u) => u.hexChanged && !u.nameChanged).toList();
    final nameOnly = updated.where((u) => u.nameChanged && !u.hexChanged).toList();

    buf.writeln('\n### ✏️ Updated colors\n');

    if (hexAndName.isNotEmpty) {
      buf.writeln('#### Hex + name changed\n');
      buf.writeln('| DMC | Old Name | New Name | Old Hex | New Hex |');
      buf.writeln('|-----|----------|----------|---------|---------|');
      for (final u in hexAndName) {
        buf.writeln(
            '| ${u.newColor.code} | ${u.oldColor.name} | ${u.newColor.name} | `#${u.oldColor.hex}` | `#${u.newColor.hex}` |');
      }
      buf.writeln();
    }

    if (hexOnly.isNotEmpty) {
      buf.writeln('#### Hex only\n');
      buf.writeln('| DMC | Name | Old Hex | New Hex |');
      buf.writeln('|-----|------|---------|---------|');
      for (final u in hexOnly) {
        buf.writeln(
            '| ${u.newColor.code} | ${u.newColor.name} | `#${u.oldColor.hex}` | `#${u.newColor.hex}` |');
      }
      buf.writeln();
    }

    if (nameOnly.isNotEmpty) {
      buf.writeln('#### Name only\n');
      buf.writeln('| DMC | Old Name | New Name | Hex |');
      buf.writeln('|-----|----------|----------|-----|');
      for (final u in nameOnly) {
        buf.writeln(
            '| ${u.newColor.code} | ${u.oldColor.name} | ${u.newColor.name} | `#${u.newColor.hex}` |');
      }
    }
  }

  File(_prBodyPath).writeAsStringSync(buf.toString());
}

// ─── GitHub Output ────────────────────────────────────────────────────────────

void _setOutput(String key, String value) {
  final path = Platform.environment['GITHUB_OUTPUT'];
  if (path != null) {
    File(path).writeAsStringSync('$key=$value\n', mode: FileMode.append);
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  print('Fetching source colors from community dataset…');
  final String sourceJson;
  try {
    sourceJson = await _get(_sourceUrl);
  } catch (e) {
    stderr.writeln('Error: could not fetch source — $e');
    exit(1);
  }

  final primaryColors = _parseSource(sourceJson);
  print('Primary source: ${primaryColors.length} colors');

  // Fetch supplementary source (KXStitch XML) for codes the primary omits.
  print('Fetching supplementary source (KXStitch XML)…');
  String supplementaryXml;
  try {
    supplementaryXml = await _get(_supplementaryUrl);
  } catch (e) {
    stderr.writeln('Warning: could not fetch supplementary source — $e');
    stderr.writeln('Continuing with primary source only.');
    supplementaryXml = '';
  }

  final primaryCodes = {for (final c in primaryColors) c.code};
  final supplementaryColors = supplementaryXml.isNotEmpty
      ? _parseSupplementary(supplementaryXml, primaryCodes)
      : <_Color>[];
  if (supplementaryColors.isNotEmpty) {
    print('Supplementary: ${supplementaryColors.length} additional codes'
        ' (e.g. ${supplementaryColors.take(3).map((c) => c.code).join(', ')}…)');
  }

  // Merged view of all known upstream colors. Primary takes precedence.
  final sourceColors = [...primaryColors, ...supplementaryColors]..sort();
  print('Source (merged): ${sourceColors.length} colors');

  final currentContent = File(_colorsPath).readAsStringSync();
  final currentColors = _parseCurrentFile(currentContent);
  print('Current: ${currentColors.length} colors');

  // Codes already handled in dmcReplacements — don't flag them again.
  final existingReplacementKeys = _parseReplacementKeys(currentContent);

  final sourceByCode = {for (final c in sourceColors) c.code: c};
  final currentByCode = {for (final c in currentColors) c.code: c};

  // Colors in source but not in app → add them.
  final added = sourceColors
      .where((c) => !currentByCode.containsKey(c.code))
      .toList();

  // Colors in app but not in source (and not already in dmcReplacements) → retire them.
  final retired = currentColors
      .where((c) =>
          !sourceByCode.containsKey(c.code) &&
          !existingReplacementKeys.contains(c.code))
      .toList();

  // Colors in both but with different name or hex in source.
  final updated = currentColors
      .where((c) {
        final s = sourceByCode[c.code];
        if (s == null) return false;
        return s.name != c.name || s.hex != c.hex;
      })
      .map((c) => _Update(c, sourceByCode[c.code]!))
      .toList();

  if (added.isEmpty && updated.isEmpty && retired.isEmpty) {
    print('No changes detected.');
    _setOutput('has_changes', 'false');
    exit(0);
  }

  // Build new dmcColors list:
  // • Keep current entries (updating name/hex where changed), excluding retired colors.
  // • Append newly added entries.
  final retiredCodes = {for (final c in retired) c.code};
  final merged = <_Color>[];
  for (final c in currentColors) {
    if (retiredCodes.contains(c.code)) continue; // removed — moved to dmcReplacements
    final s = sourceByCode[c.code];
    if (s != null && (s.name != c.name || s.hex != c.hex)) {
      merged.add(_Color(c.code, s.name, s.hex, c.anchor));
    } else {
      merged.add(c);
    }
  }
  for (final c in added) {
    merged.add(c);
  }
  merged.sort();

  // Apply changes to file.
  var newContent = currentContent;

  // Step 1: Insert placeholder entries for retired colors into dmcReplacements.
  if (retired.isNotEmpty) {
    const replHeader = 'const Map<String, String> dmcReplacements = {';
    final rs = newContent.indexOf(replHeader);
    final re = newContent.indexOf('\n};', rs + replHeader.length);
    if (rs == -1 || re == -1) {
      stderr.writeln('Error: could not find dmcReplacements map in $_colorsPath');
      exit(1);
    }
    final newEntries = retired
        .map((c) =>
            "  '${c.code}': '', // ${c.name} (#${c.hex}) — possibly retired; fill in replacement")
        .join('\n');
    newContent = '${newContent.substring(0, re)}\n$newEntries${newContent.substring(re)}';
  }

  // Step 2: Replace the dmcColors list body.
  const listHeader = 'const List<DmcColor> dmcColors = [';
  final listStart = newContent.indexOf(listHeader);
  final listBodyStart = listStart + listHeader.length;
  final listEnd = newContent.indexOf('\n];', listBodyStart);
  if (listStart == -1 || listEnd == -1) {
    stderr.writeln('Error: could not find dmcColors list in $_colorsPath');
    exit(1);
  }
  final newListBody = '\n${merged.map((c) => c.toDartLine()).join('\n')}\n';
  newContent =
      newContent.substring(0, listBodyStart) + newListBody + newContent.substring(listEnd);

  File(_colorsPath).writeAsStringSync(newContent);

  print('\nChanges applied:');
  if (added.isNotEmpty) print('  + ${added.length} added');
  if (updated.isNotEmpty) print('  ~ ${updated.length} updated (name/hex)');
  if (retired.isNotEmpty) {
    print('  - ${retired.length} moved to dmcReplacements (replacement TBD)');
  }

  _writePrBody(added: added, retired: retired, updated: updated);
  _writeChangeset(added: added, retired: retired, updated: updated);
  _setOutput('has_changes', 'true');
  _setOutput('pr_body_path', _prBodyPath);
}

void _writeChangeset({
  required List<_Color> added,
  required List<_Color> retired,
  required List<_Update> updated,
}) {
  final parts = [
    if (added.isNotEmpty) '${added.length} added',
    if (updated.isNotEmpty) '${updated.length} updated',
    if (retired.isNotEmpty) '${retired.length} possibly retired',
  ];
  final summary = parts.join(', ');

  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('"stitches": patch')
    ..writeln('---')
    ..writeln()
    ..writeln('Update DMC colour list from community source')
    ..writeln()
    ..writeln('Automated sync: $summary.');

  File(_changesetPath).writeAsStringSync(buf.toString());
  print('Changeset written to $_changesetPath');
}
