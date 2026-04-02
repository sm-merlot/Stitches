import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'package:uuid/uuid.dart';

import '../data/dmc_colors.dart';
import '../models/layer.dart';
import '../models/layer_item.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';
import '../models/thread.dart';
import 'sprite_importer.dart';

// ─── Format enum ─────────────────────────────────────────────────────────────

enum CrossStitchFormat {
  oxs('oxs', 'Open Cross Stitch (.oxs)'),
  ;

  const CrossStitchFormat(this.extension, this.label);
  final String extension;
  final String label;

  static CrossStitchFormat? forPath(String path) {
    final lower = path.toLowerCase();
    for (final f in values) {
      if (lower.endsWith('.${f.extension}')) return f;
    }
    return null;
  }
}

/// Set of file extensions (lowercase, with dot) that can be imported.
const kImportableExtensions = {'.oxs'};

// ─── Service ─────────────────────────────────────────────────────────────────

class FormatService {
  FormatService._();

  /// Imports a pattern from [path]. Throws on unrecognised format or parse error.
  static Future<CrossStitchPattern> importFile(String path) async {
    final format = CrossStitchFormat.forPath(path);
    if (format == null) throw FormatException('Unsupported format: $path');
    final content = await File(path).readAsString();
    return switch (format) {
      CrossStitchFormat.oxs => _parseOxs(content, path),
    };
  }

  /// Encodes [pattern] to a string in [format] without writing to disk.
  static String encodeFile(CrossStitchPattern pattern, CrossStitchFormat format) {
    return switch (format) {
      CrossStitchFormat.oxs => _writeOxs(pattern),
    };
  }

  /// Exports [pattern] to [path] in [format].
  static Future<void> exportFile(
      CrossStitchPattern pattern, String path, CrossStitchFormat format) async {
    await File(path).writeAsString(encodeFile(pattern, format));
  }

  // ─── OXS ───────────────────────────────────────────────────────────────────
  // WinStitch / MacStitch / Ursa Software Open Cross Stitch XML format.
  // Properties and palette items are stored as XML attributes.

  static CrossStitchPattern _parseOxs(String xmlString, String filePath) {
    final doc = XmlDocument.parse(xmlString);
    final chart = doc.rootElement;

    // ── Dimensions ────────────────────────────────────────────────────────────
    // Properties are attributes on the <properties> element, not child elements.
    final props = chart.findElements('properties').firstOrNull;
    final width = int.tryParse(props?.getAttribute('chartwidth') ?? '') ??
        int.tryParse(props?.getAttribute('stitchesacross') ?? '') ?? 10;
    final height = int.tryParse(props?.getAttribute('chartheight') ?? '') ??
        int.tryParse(props?.getAttribute('stitchesdown') ?? '') ?? 10;

    // Background colour: palette index 0 ("cloth") colour attribute.
    Color aidaColor = const Color(0xFFFFFFFF);
    final paletteElem = chart.findElements('palette').firstOrNull;
    if (paletteElem != null) {
      for (final item in paletteElem.findElements('palette_item')) {
        final idx = int.tryParse(item.getAttribute('index') ?? '');
        if (idx == 0) {
          final hex = item.getAttribute('color') ?? item.getAttribute('colour');
          if (hex != null && hex.isNotEmpty) {
            aidaColor = _parseColorHex(hex.trim());
          }
          break;
        }
      }
    }

    // ── Palette ───────────────────────────────────────────────────────────────
    // Map: palette index → Thread.  Index 0 = cloth colour, skip for stitches.
    final palette = <int, Thread>{};

    if (paletteElem != null) {
      for (final item in paletteElem.findElements('palette_item')) {
        final idx = int.tryParse(item.getAttribute('index') ?? '');
        if (idx == null || idx == 0) continue; // 0 = cloth, not a stitch colour

        // Number field may be "DMC    943", "Anchor 123", etc.
        final rawNumber = (item.getAttribute('number') ?? '').trim();
        // Strip known brand prefixes; keep only the code part.
        final number = rawNumber
            .replaceFirst(RegExp(r'^DMC\s+', caseSensitive: false), '')
            .replaceFirst(RegExp(r'^Anchor\s+', caseSensitive: false), '')
            .trim();

        final colorHex =
            item.getAttribute('color') ?? item.getAttribute('colour') ?? '';
        final name = (item.getAttribute('name') ?? '').trim();

        Thread? thread;

        // 1. Exact DMC code match.
        if (number.isNotEmpty) {
          final dmc = dmcColorByCode(number);
          if (dmc != null) {
            thread = Thread(dmcCode: dmc.code, color: dmc.color, name: dmc.name);
          }
        }

        // 2. Nearest DMC by hex colour (CIE Lab matching).
        if (thread == null && colorHex.isNotEmpty) {
          final col = _parseColorHex(colorHex.trim());
          final r = (col.r * 255).round();
          final g = (col.g * 255).round();
          final b = (col.b * 255).round();
          final match = SpriteImporter.matchPixel(r, g, b, 255);
          if (match != null) {
            thread = Thread(
              dmcCode: match.code,
              color: match.color,
              name: name.isNotEmpty ? name : match.name,
            );
          }
        }

        if (thread != null) palette[idx] = thread;
      }
    }

    // De-dup threads (two palette entries may map to the same DMC code).
    final threadMap = <String, Thread>{};
    for (final t in palette.values) {
      threadMap[t.dmcCode] = t;
    }

    // ── Stitches ──────────────────────────────────────────────────────────────
    final stitches = <Stitch>[];

    // Full stitches — <stitch x y palindex> inside <fullstitches>.
    for (final s in chart.findAllElements('stitch')) {
      final parent = s.parent;
      if (parent is! XmlElement) continue;
      if (parent.localName != 'fullstitches') continue;
      final x = int.tryParse(s.getAttribute('x') ?? '');
      final y = int.tryParse(s.getAttribute('y') ?? '');
      final pi = int.tryParse(s.getAttribute('palindex') ?? '');
      if (x == null || y == null || pi == null) continue;
      final thread = palette[pi];
      if (thread == null) continue;
      stitches.add(FullStitch(x: x, y: y, threadId: thread.dmcCode));
    }

    // Part stitches — <partstitch x y palindex1 palindex2 direction>.
    // direction: 1=\ half (palindex1), 2=/ half (palindex2),
    //            3=TL quarter, 4=BR quarter (palindex1),
    //            5=TR quarter, 6=BL quarter (palindex2).
    for (final s in chart.findAllElements('partstitch')) {
      final x = int.tryParse(s.getAttribute('x') ?? '');
      final y = int.tryParse(s.getAttribute('y') ?? '');
      final pi1 = int.tryParse(s.getAttribute('palindex1') ?? '');
      final pi2 = int.tryParse(s.getAttribute('palindex2') ?? '');
      final dir = int.tryParse(s.getAttribute('direction') ?? '1') ?? 1;
      if (x == null || y == null) continue;

      switch (dir) {
        case 1: // \ half stitch
          final thread = pi1 != null ? palette[pi1] : null;
          if (thread != null) {
            stitches.add(HalfStitch(x: x, y: y, isForward: false, threadId: thread.dmcCode));
          }
        case 2: // / half stitch
          final thread = pi2 != null ? palette[pi2] : null;
          if (thread != null) {
            stitches.add(HalfStitch(x: x, y: y, isForward: true, threadId: thread.dmcCode));
          }
        case 3: // TL quarter
          final thread = pi1 != null ? palette[pi1] : null;
          if (thread != null) {
            stitches.add(QuarterStitch(x: x, y: y, quadrant: QuadrantPosition.topLeft, threadId: thread.dmcCode));
          }
        case 4: // BR quarter
          final thread = pi1 != null ? palette[pi1] : null;
          if (thread != null) {
            stitches.add(QuarterStitch(x: x, y: y, quadrant: QuadrantPosition.bottomRight, threadId: thread.dmcCode));
          }
        case 5: // TR quarter
          final thread = pi2 != null ? palette[pi2] : null;
          if (thread != null) {
            stitches.add(QuarterStitch(x: x, y: y, quadrant: QuadrantPosition.topRight, threadId: thread.dmcCode));
          }
        case 6: // BL quarter
          final thread = pi2 != null ? palette[pi2] : null;
          if (thread != null) {
            stitches.add(QuarterStitch(x: x, y: y, quadrant: QuadrantPosition.bottomLeft, threadId: thread.dmcCode));
          }
      }
    }

    // Back stitches — <backstitch x1 y1 x2 y2 palindex>.
    for (final s in chart.findAllElements('backstitch')) {
      final x1 = double.tryParse(s.getAttribute('x1') ?? '');
      final y1 = double.tryParse(s.getAttribute('y1') ?? '');
      final x2 = double.tryParse(s.getAttribute('x2') ?? '');
      final y2 = double.tryParse(s.getAttribute('y2') ?? '');
      final pi = int.tryParse(s.getAttribute('palindex') ?? '');
      if (x1 == null || y1 == null || x2 == null || y2 == null || pi == null) {
        continue;
      }
      final thread = palette[pi];
      if (thread == null) continue;
      stitches.add(BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: thread.dmcCode));
    }

    final name = filePath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.oxs$', caseSensitive: false), '');

    return CrossStitchPattern(
      name: name,
      width: width,
      height: height,
      aidaColor: aidaColor,
      threads: threadMap.values.toList(),
      layerItems: [
        LayerLeaf(
          layer: Layer(
            id: const Uuid().v4(),
            name: 'Layer 1',
            visible: true,
            opacity: 1.0,
            stitches: stitches,
          ),
        ),
      ],
    );
  }

  static String _writeOxs(CrossStitchPattern pattern) {
    // Only include threads actually used by stitches.
    final usedIds = pattern.stitches.map((s) => s.threadId).toSet();
    final usedThreads =
        pattern.threads.where((t) => usedIds.contains(t.dmcCode)).toList();

    final palIdx = <String, int>{};
    for (var i = 0; i < usedThreads.length; i++) {
      palIdx[usedThreads[i].dmcCode] = i + 1;
    }

    final aidaHex = _hexColorNoHash(pattern.aidaColor);

    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<chart>')
      ..writeln('  <properties oxsversion="1.0" software="Stitches"'
          ' chartheight="${pattern.height}" chartwidth="${pattern.width}"'
          ' palettecount="${usedThreads.length}" />')
      ..writeln('  <palette>');

    // Cloth colour at index 0.
    buf.writeln('    <palette_item index="0" number="cloth" name="cloth"'
        ' color="$aidaHex" printcolor="$aidaHex" blendcolor="nil"'
        ' comments="" strands="2" symbol="100" dashpattern=""'
        ' bsstrands="2" bscolor="$aidaHex" />');

    for (var i = 0; i < usedThreads.length; i++) {
      final t = usedThreads[i];
      final hex = _hexColorNoHash(t.color);
      buf.writeln('    <palette_item index="${i + 1}"'
          ' number="${_esc('DMC ${t.dmcCode}')}"'
          ' name="${_esc(t.name)}"'
          ' color="$hex" printcolor="$hex" blendcolor="nil"'
          ' comments="" strands="2" symbol="${i + 1}" dashpattern=""'
          ' bsstrands="2" bscolor="$hex" />');
    }
    buf.writeln('  </palette>');

    // Full stitches.
    buf.writeln('  <fullstitches>');
    for (final s in pattern.stitches.whereType<FullStitch>()) {
      final idx = palIdx[s.threadId];
      if (idx == null) continue;
      buf.writeln('    <stitch x="${s.x}" y="${s.y}" palindex="$idx" />');
    }
    buf.writeln('  </fullstitches>');

    // Part stitches (half + quarter).
    // direction: 1=\ half (palindex1), 2=/ half (palindex2),
    //            3=TL qtr, 4=BR qtr (palindex1), 5=TR qtr, 6=BL qtr (palindex2).
    buf.writeln('  <partstitches>');
    for (final s in pattern.stitches.whereType<HalfStitch>()) {
      final idx = palIdx[s.threadId];
      if (idx == null) continue;
      if (s.isForward) {
        // / stitch → direction 2, palindex2
        buf.writeln('    <partstitch x="${s.x}" y="${s.y}"'
            ' palindex1="0" palindex2="$idx" direction="2" />');
      } else {
        // \ stitch → direction 1, palindex1
        buf.writeln('    <partstitch x="${s.x}" y="${s.y}"'
            ' palindex1="$idx" palindex2="0" direction="1" />');
      }
    }
    for (final s in pattern.stitches.whereType<QuarterStitch>()) {
      final idx = palIdx[s.threadId];
      if (idx == null) continue;
      final (dir, p1, p2) = switch (s.quadrant) {
        QuadrantPosition.topLeft => (3, idx, 0),
        QuadrantPosition.bottomRight => (4, idx, 0),
        QuadrantPosition.topRight => (5, 0, idx),
        QuadrantPosition.bottomLeft => (6, 0, idx),
      };
      buf.writeln('    <partstitch x="${s.x}" y="${s.y}"'
          ' palindex1="$p1" palindex2="$p2" direction="$dir" />');
    }
    buf.writeln('  </partstitches>');

    // Back stitches.
    buf.writeln('  <backstitches>');
    for (final s in pattern.stitches.whereType<BackStitch>()) {
      final idx = palIdx[s.threadId];
      if (idx == null) continue;
      buf.writeln('    <backstitch x1="${s.x1}" y1="${s.y1}"'
          ' x2="${s.x2}" y2="${s.y2}" palindex="$idx"'
          ' objecttype="backstitch" sequence="0" />');
    }
    buf.writeln('  </backstitches>');

    buf.writeln('</chart>');
    return buf.toString();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static Color _parseColorHex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length < 6) return const Color(0xFF000000);
    return Color(int.parse('FF${h.substring(0, 6)}', radix: 16));
  }

  /// 6-character hex without leading `#`, uppercase (e.g. `FF0000`).
  static String _hexColorNoHash(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '$r$g$b'.toUpperCase();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
