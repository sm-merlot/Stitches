import 'package:flutter/material.dart';
import '../data/dmc_colors.dart';

class Thread {
  final String dmcCode;
  final Color color;
  final String name;
  /// Single character or symbol displayed inside stitch cells on the pattern grid.
  final String symbol;

  /// Slot identity used by sprite-imported snippets. When non-null, stitches
  /// use this as their [threadId] instead of [dmcCode], allowing two slots to
  /// share the same DMC code without colliding in the pattern-threads Map.
  ///
  /// Null for all manually created snippets (backwards-compatible default).
  final String? slotId;

  const Thread({
    required this.dmcCode,
    required this.color,
    required this.name,
    this.symbol = '',
    this.slotId,
  });

  Map<String, dynamic> toYaml() => {
        'dmcCode': dmcCode,
        'color': '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}',
        'name': name,
        'symbol': symbol,
        if (slotId != null) 'slotId': slotId,
      };

  factory Thread.fromYaml(Map<String, dynamic> yaml) {
    final code = yaml['dmcCode'] as String;
    final canonical = dmcColorByCode(code);
    final Color color;
    if (canonical != null) {
      color = canonical.color;
    } else {
      final hex = (yaml['color'] as String).replaceAll('#', '');
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      color = Color.fromARGB(255, r, g, b);
    }
    return Thread(
      dmcCode: code,
      color: color,
      name: canonical?.name ?? yaml['name'] as String,
      symbol: (yaml['symbol'] as String?) ?? '',
      slotId: yaml['slotId'] as String?,
    );
  }

  Thread copyWith({
    String? dmcCode,
    Color? color,
    String? name,
    String? symbol,
    String? slotId,
    bool clearSlotId = false,
  }) {
    return Thread(
      dmcCode: dmcCode ?? this.dmcCode,
      color: color ?? this.color,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      slotId: clearSlotId ? null : (slotId ?? this.slotId),
    );
  }

  /// The effective identifier used as a stitch [threadId]: [slotId] when
  /// present (sprite imports), [dmcCode] otherwise (manual snippets).
  String get effectiveId => slotId ?? dmcCode;

  /// Parses a YAML list of thread maps into a [Map<String, Thread>] keyed by
  /// [effectiveId]. Order is preserved (Dart's [LinkedHashMap] insertion order).
  static Map<String, Thread> mapFromYaml(List<dynamic> yaml) {
    final result = <String, Thread>{};
    for (final raw in yaml) {
      final thread = Thread.fromYaml(Map<String, dynamic>.from(raw as Map));
      result[thread.effectiveId] = thread;
    }
    return result;
  }
}
