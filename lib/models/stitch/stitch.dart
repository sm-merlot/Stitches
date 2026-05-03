import 'package:flutter/foundation.dart';

/// Which quarter of a cell a stitch occupies (quarter-stitch and petit-point).
enum QuadrantPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Which half of a cell a half-cross stitch occupies (left/right = vertical split, top/bottom = horizontal split).
enum HalfOrientation { left, right, top, bottom }

sealed class Stitch {
  final String threadId;
  const Stitch({required this.threadId});

  Map<String, dynamic> toYaml();

  /// Returns a copy of this stitch with [threadId] replaced by [id].
  Stitch withThreadId(String id) => switch (this) {
        FullStitch(:final x, :final y) =>
          FullStitch(x: x, y: y, threadId: id),
        HalfStitch(:final x, :final y, :final isForward) =>
          HalfStitch(x: x, y: y, isForward: isForward, threadId: id),
        QuarterStitch(:final x, :final y, :final quadrant) =>
          QuarterStitch(x: x, y: y, quadrant: quadrant, threadId: id),
        HalfCrossStitch(:final x, :final y, :final half) =>
          HalfCrossStitch(x: x, y: y, half: half, threadId: id),
        ThreeQuarterStitch(:final x, :final y, :final quadrant, :final isForward) =>
          ThreeQuarterStitch(x: x, y: y, quadrant: quadrant, isForward: isForward, threadId: id),
        BackStitch(:final x1, :final y1, :final x2, :final y2) =>
          BackStitch(x1: x1, y1: y1, x2: x2, y2: y2, threadId: id),
      };

  static Stitch fromYaml(Map<String, dynamic> yaml) {
    final type = yaml['type'] as String;
    return switch (type) {
      'full' => FullStitch.fromYaml(yaml),
      'half' => HalfStitch.fromYaml(yaml),
      'quarter' => QuarterStitch.fromYaml(yaml),
      'halfcross' => HalfCrossStitch.fromYaml(yaml),
      'threequarter' => ThreeQuarterStitch.fromYaml(yaml),
      // Migration: old quartercross → QuarterStitch at same position.
      'quartercross' => QuarterStitch.fromYaml(yaml),
      'back' => BackStitch.fromYaml(yaml),
      _ => throw FormatException('Unknown stitch type: $type'),
    };
  }

  /// Parses a YAML list into a [List<Stitch>].
  static List<Stitch> listFromYaml(List<dynamic> yaml) =>
      yaml.map((s) => Stitch.fromYaml(Map<String, dynamic>.from(s as Map))).toList();
}

@immutable
final class FullStitch extends Stitch {
  final int x;
  final int y;

  const FullStitch({required this.x, required this.y, required super.threadId});

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'full',
        'x': x,
        'y': y,
        'thread': threadId,
      };

  factory FullStitch.fromYaml(Map<String, dynamic> yaml) => FullStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is FullStitch && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash('full', x, y);
}

@immutable
final class HalfStitch extends Stitch {
  final int x;
  final int y;

  /// true = forward `/`, false = backward `\`
  final bool isForward;

  const HalfStitch({
    required this.x,
    required this.y,
    required this.isForward,
    required super.threadId,
  });

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'half',
        'x': x,
        'y': y,
        'dir': isForward ? 'forward' : 'backward',
        'thread': threadId,
      };

  factory HalfStitch.fromYaml(Map<String, dynamic> yaml) => HalfStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        isForward: (yaml['dir'] as String) == 'forward',
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is HalfStitch &&
      other.x == x &&
      other.y == y &&
      other.isForward == isForward;

  @override
  int get hashCode => Object.hash('half', x, y, isForward);
}

@immutable
final class QuarterStitch extends Stitch {
  final int x;
  final int y;
  final QuadrantPosition quadrant;

  const QuarterStitch({
    required this.x,
    required this.y,
    required this.quadrant,
    required super.threadId,
  });

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'quarter',
        'x': x,
        'y': y,
        'quadrant': quadrant.name,
        'thread': threadId,
      };

  factory QuarterStitch.fromYaml(Map<String, dynamic> yaml) => QuarterStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        quadrant: QuadrantPosition.values.byName(yaml['quadrant'] as String),
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is QuarterStitch &&
      other.x == x &&
      other.y == y &&
      other.quadrant == quadrant;

  @override
  int get hashCode => Object.hash('quarter', x, y, quadrant);
}

/// Full cross stitch (X) placed in half a cell (rectangle shaped).
/// [half] indicates which half of the cell it occupies.
@immutable
final class HalfCrossStitch extends Stitch {
  final int x;
  final int y;
  final HalfOrientation half;

  const HalfCrossStitch({
    required this.x,
    required this.y,
    required this.half,
    required super.threadId,
  });

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'halfcross',
        'x': x,
        'y': y,
        'half': half.name,
        'thread': threadId,
      };

  factory HalfCrossStitch.fromYaml(Map<String, dynamic> yaml) => HalfCrossStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        half: HalfOrientation.values.byName(yaml['half'] as String),
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is HalfCrossStitch &&
      other.x == x &&
      other.y == y &&
      other.half == half;

  @override
  int get hashCode => Object.hash('halfcross', x, y, half);
}

/// Three-quarter stitch: a triangle covering the main diagonal plus
/// a shorter diagonal into the [quadrant] corner.
///
/// [isForward] selects the main diagonal direction: `true` = `/`, `false` = `\`.
/// [quadrant] selects which corner the triangle points into.
@immutable
final class ThreeQuarterStitch extends Stitch {
  final int x;
  final int y;
  final QuadrantPosition quadrant;

  /// Direction of the main diagonal: `true` = forward `/`, `false` = backward `\`.
  final bool isForward;

  const ThreeQuarterStitch({
    required this.x,
    required this.y,
    required this.quadrant,
    required this.isForward,
    required super.threadId,
  });

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'threequarter',
        'x': x,
        'y': y,
        'quadrant': quadrant.name,
        'dir': isForward ? 'forward' : 'backward',
        'thread': threadId,
      };

  factory ThreeQuarterStitch.fromYaml(Map<String, dynamic> yaml) => ThreeQuarterStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        quadrant: QuadrantPosition.values.byName(yaml['quadrant'] as String),
        isForward: (yaml['dir'] as String?) == 'forward',
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ThreeQuarterStitch &&
      other.x == x &&
      other.y == y &&
      other.quadrant == quadrant &&
      other.isForward == isForward;

  @override
  int get hashCode => Object.hash('threequarter', x, y, quadrant, isForward);
}

/// Backstitch connecting two grid-intersection points (at 0.5-cell increments).
/// Grid point (gx, gy) can be at full or half-cell boundaries:
///   (0,0) = top-left corner; (width, height) = bottom-right corner
@immutable
final class BackStitch extends Stitch {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BackStitch({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required super.threadId,
  });

  static dynamic _yamlNum(double v) =>
      v == v.truncateToDouble() ? v.toInt() : v;

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'back',
        'x1': _yamlNum(x1),
        'y1': _yamlNum(y1),
        'x2': _yamlNum(x2),
        'y2': _yamlNum(y2),
        'thread': threadId,
      };

  factory BackStitch.fromYaml(Map<String, dynamic> yaml) => BackStitch(
        x1: (yaml['x1'] as num).toDouble(),
        y1: (yaml['y1'] as num).toDouble(),
        x2: (yaml['x2'] as num).toDouble(),
        y2: (yaml['y2'] as num).toDouble(),
        threadId: yaml['thread'] as String,
      );

  /// Equality is order-independent: (x1,y1)→(x2,y2) == (x2,y2)→(x1,y1)
  @override
  bool operator ==(Object other) =>
      other is BackStitch &&
      ((other.x1 == x1 &&
              other.y1 == y1 &&
              other.x2 == x2 &&
              other.y2 == y2) ||
          (other.x1 == x2 &&
              other.y1 == y2 &&
              other.x2 == x1 &&
              other.y2 == y1));

  @override
  int get hashCode => Object.hash(x1, y1) ^ Object.hash(x2, y2);
}
