// Unit tests for the materials list markdown output.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/screens/materials_list_screen.dart';

void main() {
  group('buildMaterialsListMarkdown', () {
    String build({
      String patternName = 'My Pattern',
      Color aidaColor = const Color(0xFFFFFFFF),
      int aidaCount = 14,
      double widthCm = 28.0,
      double heightCm = 35.0,
      double widthIn = 11.0,
      double heightIn = 13.8,
      List<({String dmcCode, String name, int skeins})> threads = const [],
    }) =>
        buildMaterialsListMarkdown(
          patternName: patternName,
          aidaColor: aidaColor,
          aidaCount: aidaCount,
          widthCm: widthCm,
          heightCm: heightCm,
          widthIn: widthIn,
          heightIn: heightIn,
          threads: threads,
        );

    test('starts with markdown h1 containing pattern name', () {
      final out = build(patternName: 'Sunflower');
      expect(out, startsWith('# Sunflower Materials List\n'));
    });

    test('includes blank line after heading', () {
      final out = build();
      expect(out, contains('# My Pattern Materials List\n\n'));
    });

    test('aida line uses preset colour name', () {
      final out = build(aidaColor: const Color(0xFFFAF0DC)); // Antique white
      expect(out, contains('- [ ] Antique white 14-count Aida'));
    });

    test('aida line includes count and dimensions', () {
      final out = build(
        aidaCount: 18,
        widthCm: 20.5,
        heightCm: 30.1,
        widthIn: 8.1,
        heightIn: 11.9,
      );
      expect(out,
          contains('18-count Aida min 20.5 x 30.1 cm (8.1 x 11.9 in)'));
    });

    test('unknown aida colour falls back to hex', () {
      final out = build(aidaColor: const Color(0xFFABCDEF));
      expect(out, contains('- [ ] #FFABCDEF'));
    });

    test('thread line format', () {
      final out = build(threads: [
        (dmcCode: '310', name: 'Black', skeins: 2),
      ]);
      expect(out, contains('- [ ] DMC 310 Black x 2 skeins'));
    });

    test('single skein uses singular', () {
      final out = build(threads: [
        (dmcCode: '321', name: 'Red', skeins: 1),
      ]);
      expect(out, contains('x 1 skein\n'));
    });

    test('multiple threads all appear', () {
      final out = build(threads: [
        (dmcCode: '310', name: 'Black', skeins: 2),
        (dmcCode: '321', name: 'Red', skeins: 1),
        (dmcCode: 'blanc', name: 'White', skeins: 3),
      ]);
      expect(out, contains('DMC 310 Black'));
      expect(out, contains('DMC 321 Red'));
      expect(out, contains('DMC blanc White'));
    });

    test('output with no threads contains only heading and aida line', () {
      final lines = build().trimRight().split('\n');
      // heading, blank, aida
      expect(lines.length, 3);
    });
  });
}
