// Fetches the latest DMC thread color list and updates lib/data/dmc_colors.dart.
//
// Source: cheshire137/cross-stitch-color-conversion (JSON, ~447 colors)
//
// What it does:
//   • Adds colors present in the source but missing from the app list.
//   • Removes colors absent from the source: moves them out of dmcColors and
//     adds placeholder entries (empty replacement) to dmcReplacements so they
//     show up in the PR for review. Fill in the replacement before merging, or
//     revert the change if it turns out to be a false alarm.
//   • Updates name/hex for colors whose details changed in the source.
//   • Never overwrites existing Anchor codes; preserves them on updates.
//   • Writes tool/.pr_body.md and sets GITHUB_OUTPUT for CI use.
//
// Usage:
//   dart run tool/update_dmc_colors.dart

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _sourceUrl = 'https://raw.githubusercontent.com/'
    'cheshire137/cross-stitch-color-conversion/'
    'main/src/assets/dmc-color-codes-names.json';

const _colorsPath = 'lib/data/dmc_colors.dart';
const _prBodyPath = 'tool/.pr_body.md';

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
      (m['hexCode'] as String).trim().toUpperCase(),
    );
  }).toList()
    ..sort());
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

// ─── PR body ──────────────────────────────────────────────────────────────────

void _writePrBody({
  required List<_Color> added,
  required List<_Color> retired,
  required List<_Color> updated,
}) {
  final buf = StringBuffer();

  final total = added.length + retired.length + updated.length;
  buf.writeln('## DMC Color List Update\n');
  buf.writeln('Automated monthly sync against the '
      '[cheshire137/cross-stitch-color-conversion]'
      '(https://github.com/cheshire137/cross-stitch-color-conversion) dataset.\n');

  if (total == 0) {
    buf.writeln('No changes detected.');
  } else {
    final parts = [
      if (added.isNotEmpty) '**${added.length} added**',
      if (retired.isNotEmpty)
        '**${retired.length} possibly retired** (removed from list, replacement TBD)',
      if (updated.isNotEmpty) '**${updated.length} updated** (name or hex changed)',
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
    buf.writeln('\n### ✏️ Name or hex updated\n');
    buf.writeln('| DMC | Name | New Hex |');
    buf.writeln('|-----|------|---------|');
    for (final c in updated) {
      buf.writeln('| ${c.code} | ${c.name} | `#${c.hex}` |');
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

  final sourceColors = _parseSource(sourceJson);
  print('Source: ${sourceColors.length} colors');

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
  final updated = currentColors.where((c) {
    final s = sourceByCode[c.code];
    if (s == null) return false;
    return s.name != c.name || s.hex != c.hex;
  }).toList();

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
  _setOutput('has_changes', 'true');
}
