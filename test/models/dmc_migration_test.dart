// Tests for automatic migration of discontinued DMC thread codes on pattern load.
//
// Coverage:
//   • Discontinued thread replaced with correct code/color/name from DMC database
//   • User-assigned symbol is preserved through migration
//   • All stitch threadId references are updated in all layers
//   • If replacement already in palette, discontinued entry is dropped (no duplicate)
//   • Snippet palette threads and stitches are migrated
//   • editorSelectedThreadId is remapped
//   • Current patterns (no discontinued codes) are returned unchanged

import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/data/dmc_colors.dart';
import 'package:stitches/models/pattern.dart';

/// Minimal YAML map for a CrossStitchPattern.
Map<String, dynamic> _baseYaml({
  List<Map<String, dynamic>> threads = const [],
  List<Map<String, dynamic>> stitches = const [],
  String? selectedThread,
  List<Map<String, dynamic>> snippets = const [],
}) =>
    {
      'name': 'Test',
      'width': 10,
      'height': 10,
      'threads': threads,
      'stitches': stitches,
      if (selectedThread != null) 'editor': {'selectedThread': selectedThread},
      'snippets': snippets,
    };

Map<String, dynamic> _thread(String code, {String symbol = ''}) => {
      'dmcCode': code,
      'color': '#FF0000',
      'name': 'Old Name',
      'symbol': symbol,
    };

Map<String, dynamic> _fullStitch(int x, int y, String thread) =>
    {'type': 'full', 'x': x, 'y': y, 'thread': thread};

void main() {
  group('DMC discontinued-thread migration', () {
    test('discontinued thread is replaced with correct replacement code', () {
      final p = CrossStitchPattern.fromYaml(
          _baseYaml(threads: [_thread('971')]));
      expect(p.threads, hasLength(1));
      expect(p.threads.values.first.dmcCode, '740');
    });

    test('replacement color and name come from DMC database', () {
      final p = CrossStitchPattern.fromYaml(
          _baseYaml(threads: [_thread('971')]));
      final dmc = dmcColorByCode('740')!;
      expect(p.threads.values.first.color, dmc.color);
      expect(p.threads.values.first.name, dmc.name);
    });

    test('user-assigned symbol is preserved through migration', () {
      final p = CrossStitchPattern.fromYaml(
          _baseYaml(threads: [_thread('971', symbol: 'P')]));
      expect(p.threads.values.first.symbol, 'P');
    });

    test('stitch threadId references are remapped in all layers', () {
      final p = CrossStitchPattern.fromYaml(_baseYaml(
        threads: [_thread('971')],
        stitches: [
          _fullStitch(0, 0, '971'),
          _fullStitch(1, 0, '971'),
        ],
      ));
      for (final s in p.stitches) {
        expect(s.threadId, '740',
            reason: 'all stitches should reference the replacement code');
      }
    });

    test('all 8 known discontinued codes are remapped', () {
      for (final entry in dmcReplacements.entries) {
        final p = CrossStitchPattern.fromYaml(_baseYaml(
          threads: [_thread(entry.key)],
          stitches: [_fullStitch(0, 0, entry.key)],
        ));
        expect(p.threads.values.first.dmcCode, entry.value,
            reason: '${entry.key} should become ${entry.value}');
        expect(p.stitches.first.threadId, entry.value);
      }
    });

    test('no duplicate thread when replacement already exists in palette', () {
      // Pattern has both 971 (discontinued) and 740 (its replacement).
      final p = CrossStitchPattern.fromYaml(_baseYaml(
        threads: [_thread('971'), _thread('740')],
        stitches: [_fullStitch(0, 0, '971'), _fullStitch(1, 0, '740')],
      ));
      // 971 should be dropped; only 740 remains.
      expect(p.threads, hasLength(1));
      expect(p.threads.values.first.dmcCode, '740');
      // Stitches from 971 are remapped to 740.
      expect(p.stitches.every((s) => s.threadId == '740'), isTrue);
    });

    test('editorSelectedThreadId is remapped', () {
      final p = CrossStitchPattern.fromYaml(_baseYaml(
        threads: [_thread('971')],
        selectedThread: '971',
      ));
      expect(p.editorSelectedThreadId, '740');
    });

    test('snippet palette threads and stitches are migrated', () {
      final p = CrossStitchPattern.fromYaml(_baseYaml(
        threads: [_thread('310')], // main pattern uses a current thread
        snippets: [
          {
            'id': 'snip-1',
            'name': 'My Snippet',
            'width': 5,
            'height': 5,
            'palettes': [
              {
                'id': 'pal-1',
                'name': 'Palette 1',
                'threads': [_thread('971', symbol: 'Q')],
              }
            ],
            'stitches': [_fullStitch(0, 0, '971')],
          }
        ],
      ));
      final snippet = p.snippets.first;
      expect(snippet.palettes.first.threads.first.dmcCode, '740');
      expect(snippet.palettes.first.threads.first.symbol, 'Q');
      expect(snippet.stitches.first.threadId, '740');
    });

    test('current patterns with no discontinued codes are unchanged', () {
      final p = CrossStitchPattern.fromYaml(_baseYaml(
        threads: [_thread('310'), _thread('740')],
        stitches: [_fullStitch(0, 0, '310'), _fullStitch(1, 0, '740')],
      ));
      expect(p.threads.values.map((t) => t.dmcCode).toList(), ['310', '740']);
      expect(p.stitches[0].threadId, '310');
      expect(p.stitches[1].threadId, '740');
    });
  });
}
