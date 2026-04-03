// Fetches the latest DMC thread color list and updates lib/data/dmc_colors.dart.
//
// Source: cheshire137/cross-stitch-color-conversion (JSON, ~447 colors)
//
// What it does:
//   • Adds colors present in the source but missing from the app list.
//   • Flags colors in the app list but absent from the source (potentially
//     retired) — prints them but does NOT remove them automatically.
//   • Never overwrites existing Anchor codes; preserves them on updates.
//   • If ANTHROPIC_API_KEY is set, asks Claude for Anchor equivalents of any
//     newly added colors and includes the suggestions in the PR body.
//   • Writes tool/.pr_body.md and sets GITHUB_OUTPUT for CI use.
//
// Usage:
//   dart run tool/update_dmc_colors.dart
//
// CI usage (set ANTHROPIC_API_KEY secret to enable Anchor suggestions):
//   env ANTHROPIC_API_KEY=sk-... dart run tool/update_dmc_colors.dart

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

// ─── Anchor lookup via Claude ─────────────────────────────────────────────────

Future<Map<String, String?>> _lookupAnchorCodes(
    List<_Color> colors, String apiKey) async {
  if (colors.isEmpty) return {};

  final colorList =
      colors.map((c) => '  ${c.code.padRight(6)} ${c.name}').join('\n');

  final prompt = 'For each DMC embroidery thread below, provide the closest '
      'Anchor equivalent thread code. Return ONLY a JSON object mapping DMC '
      'code → Anchor code string. Use null if no equivalent exists.\n\n'
      '$colorList';

  final requestBody = jsonEncode({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 1024,
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
  });

  final client = HttpClient();
  try {
    final req = await client
        .postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
    req.headers
      ..set('content-type', 'application/json')
      ..set('x-api-key', apiKey)
      ..set('anthropic-version', '2023-06-01');
    req.write(requestBody);

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();

    if (res.statusCode != 200) {
      print('Warning: Anchor lookup returned HTTP ${res.statusCode}');
      return {};
    }

    final text =
        ((jsonDecode(body) as Map)['content'] as List).first['text'] as String;

    // Extract the JSON block from the response.
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) return {};

    final parsed = jsonDecode(text.substring(start, end + 1)) as Map;
    return parsed.map((k, v) => MapEntry(k as String, v as String?));
  } catch (e) {
    print('Warning: Anchor lookup failed — $e');
    return {};
  } finally {
    client.close(force: true);
  }
}

// ─── PR body ──────────────────────────────────────────────────────────────────

void _writePrBody({
  required List<_Color> added,
  required List<_Color> potentiallyRetired,
  required List<_Color> updated,
  required Map<String, String?> anchorSuggestions,
}) {
  final buf = StringBuffer();

  final total = added.length + potentiallyRetired.length + updated.length;
  buf.writeln('## DMC Color List Update\n');
  buf.writeln('Automated monthly sync against the '
      '[cheshire137/cross-stitch-color-conversion]'
      '(https://github.com/cheshire137/cross-stitch-color-conversion) dataset.\n');

  if (total == 0) {
    buf.writeln('No changes detected.');
  } else {
    final parts = [
      if (added.isNotEmpty) '**${added.length} added**',
      if (potentiallyRetired.isNotEmpty)
        '**${potentiallyRetired.length} possibly retired** (not auto-removed — needs review)',
      if (updated.isNotEmpty) '**${updated.length} updated** (name or hex changed)',
    ];
    buf.writeln(parts.join(' · '));
  }

  if (added.isNotEmpty) {
    buf.writeln('\n### ➕ New colors\n');
    final hasAnchors = anchorSuggestions.isNotEmpty;
    if (hasAnchors) {
      buf.writeln(
          '> Anchor suggestions below were generated by Claude — please verify before merging.\n');
      buf.writeln('| DMC | Name | Hex | Suggested Anchor |');
      buf.writeln('|-----|------|-----|-----------------|');
      for (final c in added) {
        final anchor = anchorSuggestions[c.code];
        final anchorCell = anchor ?? '—';
        buf.writeln('| ${c.code} | ${c.name} | `#${c.hex}` | $anchorCell |');
      }
    } else {
      buf.writeln(
          '> Anchor codes not auto-looked up. Set `ANTHROPIC_API_KEY` secret to enable suggestions, '
          'or add them manually in `lib/data/dmc_colors.dart`.\n');
      buf.writeln('| DMC | Name | Hex |');
      buf.writeln('|-----|------|-----|');
      for (final c in added) {
        buf.writeln('| ${c.code} | ${c.name} | `#${c.hex}` |');
      }
    }
  }

  if (potentiallyRetired.isNotEmpty) {
    buf.writeln('\n### ⚠️ Not found in source (possibly retired)\n');
    buf.writeln(
        'These colors are in the app list but absent from the community source. '
        'They have **not** been removed automatically.\n'
        'If confirmed discontinued, add them to `dmcReplacements` in '
        '`lib/data/dmc_colors.dart` with the best replacement, then remove the entry.\n');
    buf.writeln('| DMC | Name | Hex | Current Anchor |');
    buf.writeln('|-----|------|-----|----------------|');
    for (final c in potentiallyRetired) {
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

  final sourceByCode = {for (final c in sourceColors) c.code: c};
  final currentByCode = {for (final c in currentColors) c.code: c};

  // Colours in source but not in app → add them.
  final added = sourceColors
      .where((c) => !currentByCode.containsKey(c.code))
      .toList();

  // Colours in app but not in source → flag for review.
  final potentiallyRetired = currentColors
      .where((c) => !sourceByCode.containsKey(c.code))
      .toList();

  // Colours in both but with different name or hex in source.
  final updated = currentColors.where((c) {
    final s = sourceByCode[c.code];
    if (s == null) return false;
    return s.name != c.name || s.hex != c.hex;
  }).toList();

  if (added.isEmpty && updated.isEmpty) {
    print('No changes to apply.');
    if (potentiallyRetired.isNotEmpty) {
      print(
          '\n⚠️  ${potentiallyRetired.length} color(s) not found in source '
          '(not auto-removed):');
      for (final c in potentiallyRetired) {
        print('  ${c.code.padRight(6)} ${c.name}');
      }
    }
    _setOutput('has_changes', 'false');
    exit(0);
  }

  // Build new merged list:
  // • Keep all current entries (updating name/hex from source where changed).
  // • Append newly added entries.
  // • Never remove entries — retirements are flagged but handled manually.
  final merged = <_Color>[];
  for (final c in currentColors) {
    final s = sourceByCode[c.code];
    if (s != null && (s.name != c.name || s.hex != c.hex)) {
      // Update name and hex from source; preserve Anchor code.
      merged.add(_Color(c.code, s.name, s.hex, c.anchor));
    } else {
      merged.add(c);
    }
  }
  for (final c in added) {
    merged.add(c); // anchor is null until looked up
  }
  merged.sort();

  // Find the list boundaries in the current file and replace only that section.
  const listHeader = 'const List<DmcColor> dmcColors = [';
  final listStart = currentContent.indexOf(listHeader);
  final listBodyStart = listStart + listHeader.length;
  final listEnd = currentContent.indexOf('\n];', listBodyStart);
  if (listStart == -1 || listEnd == -1) {
    stderr.writeln('Error: could not find dmcColors list in $_colorsPath');
    exit(1);
  }

  final newListBody = '\n${merged.map((c) => c.toDartLine()).join('\n')}\n';
  final newContent = currentContent.substring(0, listBodyStart) +
      newListBody +
      currentContent.substring(listEnd);

  File(_colorsPath).writeAsStringSync(newContent);

  print('\nChanges applied:');
  if (added.isNotEmpty) print('  + ${added.length} added');
  if (updated.isNotEmpty) print('  ~ ${updated.length} updated (name/hex)');
  if (potentiallyRetired.isNotEmpty) {
    print(
        '  ? ${potentiallyRetired.length} not in source (flagged, not removed)');
  }

  // Optionally look up Anchor codes for new colors via Claude.
  var anchorSuggestions = <String, String?>{};
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey != null && added.isNotEmpty) {
    print('\nLooking up Anchor codes for ${added.length} new color(s)…');
    anchorSuggestions = await _lookupAnchorCodes(added, apiKey);
    print('Got ${anchorSuggestions.length} suggestions.');
  }

  _writePrBody(
    added: added,
    potentiallyRetired: potentiallyRetired,
    updated: updated,
    anchorSuggestions: anchorSuggestions,
  );

  _setOutput('has_changes', 'true');
}
