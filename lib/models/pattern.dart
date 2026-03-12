import 'package:flutter/material.dart';
import 'stitch.dart';
import 'thread.dart';

class CrossStitchPattern {
  final String name;
  final int width;
  final int height;
  final List<Thread> threads;
  final List<Stitch> stitches;
  final Color aidaColor;

  /// Last-saved editor state — which thread was active.
  final String? editorSelectedThreadId;

  /// Last-saved editor state — which tool was active (DrawingTool.name).
  final String? editorTool;

  const CrossStitchPattern({
    required this.name,
    required this.width,
    required this.height,
    required this.threads,
    required this.stitches,
    this.aidaColor = Colors.white,
    this.editorSelectedThreadId,
    this.editorTool,
  });

  factory CrossStitchPattern.empty({
    String name = 'New Pattern',
    int width = 30,
    int height = 30,
  }) {
    return CrossStitchPattern(
      name: name,
      width: width,
      height: height,
      threads: const [],
      stitches: const [],
    );
  }

  CrossStitchPattern copyWith({
    String? name,
    int? width,
    int? height,
    List<Thread>? threads,
    List<Stitch>? stitches,
    Color? aidaColor,
    Object? editorSelectedThreadId = _sentinel,
    Object? editorTool = _sentinel,
  }) {
    return CrossStitchPattern(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      threads: threads ?? this.threads,
      stitches: stitches ?? this.stitches,
      aidaColor: aidaColor ?? this.aidaColor,
      editorSelectedThreadId: editorSelectedThreadId == _sentinel
          ? this.editorSelectedThreadId
          : editorSelectedThreadId as String?,
      editorTool: editorTool == _sentinel
          ? this.editorTool
          : editorTool as String?,
    );
  }

  static const _sentinel = Object();

  Thread? threadByCode(String dmcCode) {
    return threads.where((t) => t.dmcCode == dmcCode).firstOrNull;
  }

  /// Hex string representation of [aidaColor], e.g. `'#FFFFFF'`.
  String get aidaColorHex {
    final argb = aidaColor.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color _parseHex(String hex) {
    final h = hex.startsWith('#') ? hex.substring(1) : hex;
    return Color(int.parse('FF$h', radix: 16));
  }

  factory CrossStitchPattern.fromYaml(Map yaml) {
    final editor = yaml['editor'] as Map?;
    final aidaHex = yaml['aidaColor'] as String?;
    return CrossStitchPattern(
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      aidaColor: aidaHex != null ? _parseHex(aidaHex) : Colors.white,
      editorSelectedThreadId: editor?['selectedThread'] as String?,
      editorTool: editor?['tool'] as String?,
      threads: (yaml['threads'] as List?)
              ?.map((t) => Thread.fromYaml(t as Map))
              .toList() ??
          [],
      stitches: (yaml['stitches'] as List?)
              ?.map((s) => Stitch.fromYaml(s as Map))
              .toList() ??
          [],
    );
  }
}
