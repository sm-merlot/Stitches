import 'package:flutter/material.dart';

class Thread {
  final String dmcCode;
  final Color color;
  final String name;
  /// Single character or symbol displayed inside stitch cells on the pattern grid.
  final String symbol;

  const Thread({
    required this.dmcCode,
    required this.color,
    required this.name,
    this.symbol = '',
  });

  Map<String, dynamic> toYaml() => {
        'dmcCode': dmcCode,
        'color': '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}',
        'name': name,
        'symbol': symbol,
      };

  factory Thread.fromYaml(Map<String, dynamic> yaml) {
    final hex =
        (yaml['color'] as String).replaceAll('#', '');
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    return Thread(
      dmcCode: yaml['dmcCode'] as String,
      color: Color.fromARGB(255, r, g, b),
      name: yaml['name'] as String,
      symbol: (yaml['symbol'] as String?) ?? '',
    );
  }

  Thread copyWith({String? dmcCode, Color? color, String? name, String? symbol}) {
    return Thread(
      dmcCode: dmcCode ?? this.dmcCode,
      color: color ?? this.color,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
    );
  }
}
