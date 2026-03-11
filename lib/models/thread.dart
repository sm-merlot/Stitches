import 'package:flutter/material.dart';

class Thread {
  final String id;
  final String code;
  final Color color;
  final String name;

  const Thread({
    required this.id,
    required this.code,
    required this.color,
    required this.name,
  });

  Map<String, dynamic> toYaml() => {
        'id': id,
        'code': code,
        'color': '#${color.r.round().toRadixString(16).padLeft(2, '0')}'
            '${color.g.round().toRadixString(16).padLeft(2, '0')}'
            '${color.b.round().toRadixString(16).padLeft(2, '0')}',
        'name': name,
      };

  factory Thread.fromYaml(Map yaml) {
    final hex = (yaml['color'] as String).replaceAll('#', '');
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    return Thread(
      id: yaml['id'] as String,
      code: yaml['code'] as String,
      color: Color.fromARGB(255, r, g, b),
      name: yaml['name'] as String,
    );
  }

  Thread copyWith({String? id, String? code, Color? color, String? name}) {
    return Thread(
      id: id ?? this.id,
      code: code ?? this.code,
      color: color ?? this.color,
      name: name ?? this.name,
    );
  }
}
