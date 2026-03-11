import 'package:flutter/foundation.dart';

enum QuadrantPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Orientation for a half-cell cross stitch
enum HalfOrientation { left, right, top, bottom }

sealed class Stitch {
  final String threadId;
  const Stitch({required this.threadId});

  Map<String, dynamic> toYaml();

  static Stitch fromYaml(Map yaml) {
    final type = yaml['type'] as String;
    return switch (type) {
      'full' => FullStitch.fromYaml(yaml),
      'half' => HalfStitch.fromYaml(yaml),
      'quarter' => QuarterStitch.fromYaml(yaml),
      'halfcross' => HalfCrossStitch.fromYaml(yaml),
      'quartercross' => QuarterCrossStitch.fromYaml(yaml),
      'back' => BackStitch.fromYaml(yaml),
      _ => throw FormatException('Unknown stitch type: $type'),
    };
  }
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

  factory FullStitch.fromYaml(Map yaml) => FullStitch(
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

  factory HalfStitch.fromYaml(Map yaml) => HalfStitch(
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

  factory QuarterStitch.fromYaml(Map yaml) => QuarterStitch(
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

  factory HalfCrossStitch.fromYaml(Map yaml) => HalfCrossStitch(
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

/// Full cross stitch (X) placed in a quarter of a cell (petit point).
/// Four of these fit inside one regular full stitch cell.
@immutable
final class QuarterCrossStitch extends Stitch {
  final int x;
  final int y;
  final QuadrantPosition quadrant;

  const QuarterCrossStitch({
    required this.x,
    required this.y,
    required this.quadrant,
    required super.threadId,
  });

  @override
  Map<String, dynamic> toYaml() => {
        'type': 'quartercross',
        'x': x,
        'y': y,
        'quadrant': quadrant.name,
        'thread': threadId,
      };

  factory QuarterCrossStitch.fromYaml(Map yaml) => QuarterCrossStitch(
        x: yaml['x'] as int,
        y: yaml['y'] as int,
        quadrant: QuadrantPosition.values.byName(yaml['quadrant'] as String),
        threadId: yaml['thread'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is QuarterCrossStitch &&
      other.x == x &&
      other.y == y &&
      other.quadrant == quadrant;

  @override
  int get hashCode => Object.hash('quartercross', x, y, quadrant);
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

  factory BackStitch.fromYaml(Map yaml) => BackStitch(
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
