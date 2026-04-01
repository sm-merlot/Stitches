import 'package:flutter/material.dart';

const aidaPresets = [
  (label: 'White',         color: Color(0xFFFFFFFF)),
  (label: 'Antique white', color: Color(0xFFFAF0DC)),
  (label: 'Cream',         color: Color(0xFFFFF8DC)),
  (label: 'Light grey',    color: Color(0xFFD8D8D8)),
  (label: 'Mid grey',      color: Color(0xFF888888)),
  (label: 'Charcoal',      color: Color(0xFF404040)),
  (label: 'Black',         color: Color(0xFF1A1A1A)),
  (label: 'Navy',          color: Color(0xFF1B2A4A)),
  (label: 'Sage green',    color: Color(0xFF7A9E7E)),
  (label: 'Sky blue',      color: Color(0xFFB0C8E0)),
  (label: 'Dusty rose',    color: Color(0xFFD4A0A0)),
  (label: 'Burgundy',      color: Color(0xFF6B1A1A)),
];

String aidaColorLabel(Color color) {
  final match = aidaPresets.where((p) => p.color.toARGB32() == color.toARGB32());
  return match.isNotEmpty ? match.first.label : '#${color.toARGB32().toRadixString(16).toUpperCase()}';
}
