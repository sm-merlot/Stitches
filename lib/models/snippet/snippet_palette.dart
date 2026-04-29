import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../thread.dart';

@immutable
class SnippetPalette {
  final String id;
  final String name;
  /// Ordered thread list — index position defines the "slot".
  final List<Thread> threads;

  const SnippetPalette({
    required this.id,
    required this.name,
    required this.threads,
  });

  factory SnippetPalette.create({
    String? name,
    List<Thread> threads = const [],
  }) {
    return SnippetPalette(
      id: const Uuid().v4(),
      name: name ?? 'Palette 1',
      threads: threads,
    );
  }

  SnippetPalette copyWith({
    String? name,
    List<Thread>? threads,
  }) {
    return SnippetPalette(
      id: id,
      name: name ?? this.name,
      threads: threads ?? this.threads,
    );
  }

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'threads': threads.map((t) => t.toYaml()).toList(),
      };

  factory SnippetPalette.fromYaml(Map<String, dynamic> yaml) {
    return SnippetPalette(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      threads: (yaml['threads'] as List?)
              ?.map((t) =>
                  Thread.fromYaml(Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
    );
  }
}
