enum StitchType {
  frontOne,
  frontTwo,
  backOne,
  backTwo,
  backThree,
  automatic,
}

enum Corner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

typedef StitchPoint = ({int squareId, Corner corner});

sealed class PlanStitchEntry {
  const PlanStitchEntry();
  StitchType get type;
}

class PlanSimpleStitch extends PlanStitchEntry {
  final int squareId;
  final Corner fro;
  final Corner to;
  @override
  final StitchType type;

  const PlanSimpleStitch({
    required this.squareId,
    required this.fro,
    required this.to,
    this.type = StitchType.automatic,
  });
}

class PlanCrossStitch extends PlanStitchEntry {
  final StitchPoint fro;
  final StitchPoint to;
  @override
  final StitchType type;

  const PlanCrossStitch({
    required this.fro,
    required this.to,
    required this.type,
  });
}

/// A square in the planned grid.
///
/// Corner coordinates use screen coordinates (y=0 at top, y increases downward):
///   topLeft:     (x - 0.5, y - 0.5)
///   topRight:    (x + 0.5, y - 0.5)
///   bottomLeft:  (x - 0.5, y + 0.5)
///   bottomRight: (x + 0.5, y + 0.5)
class PlannedSquare {
  final int id;
  final int x;
  final int y;

  const PlannedSquare({required this.id, required this.x, required this.y});

  (double, double) cornerCoord(Corner corner) => switch (corner) {
        Corner.topLeft => (x - 0.5, y - 0.5),
        Corner.topRight => (x + 0.5, y - 0.5),
        Corner.bottomLeft => (x - 0.5, y + 0.5),
        Corner.bottomRight => (x + 0.5, y + 0.5),
      };
}

class PlannedAida {
  final String title;
  final int cols;
  final int rows;

  /// All non-removed squares in the grid, indexed by squareId.
  /// Includes both active (stitched) and inactive squares.
  final List<PlannedSquare> squares;

  /// The squareIds that are being stitched (the active cells).
  final Set<int> activeSquareIds;

  /// Pass 1 schedule: ordered list of ops as "S1(x,y)" / "S2(x,y)" strings.
  final List<String> schedule;

  /// The planned stitch sequence: [PlanSimpleStitch | PlanCrossStitch].
  final List<PlanStitchEntry> stitches;

  const PlannedAida({
    required this.title,
    required this.cols,
    required this.rows,
    required this.squares,
    required this.activeSquareIds,
    this.schedule = const [],
    required this.stitches,
  });
}
