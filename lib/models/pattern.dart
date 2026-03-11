import 'stitch.dart';
import 'thread.dart';

class CrossStitchPattern {
  final String name;
  final int width;
  final int height;
  final List<Thread> threads;
  final List<Stitch> stitches;

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
    Object? editorSelectedThreadId = _sentinel,
    Object? editorTool = _sentinel,
  }) {
    return CrossStitchPattern(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      threads: threads ?? this.threads,
      stitches: stitches ?? this.stitches,
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

  Map<String, dynamic> toYaml() => {
        'name': name,
        'width': width,
        'height': height,
        if (editorSelectedThreadId != null || editorTool != null)
          'editor': {
            if (editorSelectedThreadId != null)
              'selectedThread': editorSelectedThreadId,
            if (editorTool != null) 'tool': editorTool,
          },
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory CrossStitchPattern.fromYaml(Map yaml) {
    final editor = yaml['editor'] as Map?;
    return CrossStitchPattern(
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
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
