import 'package:uuid/uuid.dart';
import 'stitch.dart';
import 'thread.dart';

class Snippet {
  final String id;
  final String name;
  final int width;
  final int height;
  final List<Thread> threads;
  final List<Stitch> stitches;

  const Snippet({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.threads,
    required this.stitches,
  });

  factory Snippet.create({
    required String name,
    required int width,
    required int height,
    List<Thread> threads = const [],
    List<Stitch> stitches = const [],
  }) {
    return Snippet(
      id: const Uuid().v4(),
      name: name,
      width: width,
      height: height,
      threads: threads,
      stitches: stitches,
    );
  }

  Snippet copyWith({
    String? name,
    int? width,
    int? height,
    List<Thread>? threads,
    List<Stitch>? stitches,
  }) {
    return Snippet(
      id: id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      threads: threads ?? this.threads,
      stitches: stitches ?? this.stitches,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'threads': threads.map((t) => t.toYaml()).toList(),
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory Snippet.fromYaml(Map<String, dynamic> yaml) {
    return Snippet(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      width: yaml['width'] as int,
      height: yaml['height'] as int,
      threads: (yaml['threads'] as List?)
              ?.map((t) => Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
      stitches: (yaml['stitches'] as List?)
              ?.map((s) => Stitch.fromYaml(Map<String, dynamic>.from(s as Map)))
              .toList() ??
          [],
    );
  }
}
