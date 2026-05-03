import 'package:uuid/uuid.dart';
import '../cell.dart';
import 'layer_blend_mode.dart';
import '../stitch/stitch.dart';
import '../stitch/stitch_geometry.dart';

class Layer {
  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final LayerBlendMode blendMode;

  // ── Primary storage ──────────────────────────────────────────────────────────
  //
  // Non-backstitch stitches are stored in [stitchesByCell], keyed by their
  // (x, y) cell coordinate for O(1) per-cell lookup.  [BackStitch] has no
  // single-cell coordinate and lives in [backstitches].
  //
  // The cell index is built once (at construction time or on [copyWith] with a
  // stitch list) and is never discarded.  Incremental update methods
  // ([withStitchAdded] etc.) copy only the map — O(N_cells) — rather than
  // triggering a full O(N_stitches) rebuild after every mutation.

  /// Non-backstitch stitches keyed by cell.  O(1) per-cell lookup.
  final Map<Cell, List<Stitch>> stitchesByCell;

  /// All backstitches in this layer (no single cell coordinate).
  final List<BackStitch> backstitches;

  // ── Internal constructor ─────────────────────────────────────────────────────

  Layer._({
    required this.id,
    required this.name,
    required this.visible,
    required this.locked,
    required this.opacity,
    required this.blendMode,
    required this.stitchesByCell,
    required this.backstitches,
  });

  // ── Public constructors ──────────────────────────────────────────────────────

  /// Creates a [Layer] from a flat [stitches] list.
  ///
  /// Builds [stitchesByCell] immediately so [stitchesAt] is always O(1).
  /// Call sites that already have a map can use the named [Layer.fromMap]
  /// constructor to skip the O(N) index build.
  factory Layer({
    required String id,
    required String name,
    required bool visible,
    bool locked = false,
    required double opacity,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    required List<Stitch> stitches,
  }) {
    final (:byCell, :back) = _indexList(stitches);
    return Layer._(
      id: id,
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      blendMode: blendMode,
      stitchesByCell: byCell,
      backstitches: back,
    );
  }

  factory Layer.create({String? name}) {
    return Layer._(
      id: const Uuid().v4(),
      name: name ?? 'Layer 1',
      visible: true,
      locked: false,
      opacity: 1.0,
      blendMode: LayerBlendMode.normal,
      stitchesByCell: {},
      backstitches: [],
    );
  }

  // ── Index builder ────────────────────────────────────────────────────────────

  static ({Map<Cell, List<Stitch>> byCell, List<BackStitch> back}) _indexList(
      List<Stitch> stitches) {
    final byCell = <Cell, List<Stitch>>{};
    final back = <BackStitch>[];
    for (final s in stitches) {
      if (s is BackStitch) {
        back.add(s);
      } else {
        final c = s.cellCoords;
        if (c != null) (byCell[c] ??= []).add(s);
      }
    }
    return (byCell: byCell, back: back);
  }

  // ── Compatibility getter ─────────────────────────────────────────────────────

  /// All stitches — cell stitches first (in cell-iteration order), backstitches
  /// last.  Allocates a new list on every call; use sparingly (serialisation,
  /// bulk transforms).  Hot-path code should use [stitchesByCell] /
  /// [backstitches] directly, or [stitchesAt] for per-cell access.
  List<Stitch> get stitches => [
        for (final list in stitchesByCell.values) ...list,
        ...backstitches,
      ];

  // ── O(1) cell lookup ─────────────────────────────────────────────────────────

  /// All non-backstitch stitches at cell ([x], [y]).  O(1).
  List<Stitch> stitchesAt(int x, int y) =>
      stitchesByCell[Cell(x, y)] ?? const [];

  // ── Immutable update methods ────────────────────────────────────────────────
  //
  // Each returns a new [Layer] sharing the same metadata.  [stitchesByCell] is
  // shallow-copied (O(N_cells)) and the target cell is updated in-place.
  // BackStitch variants copy [backstitches] instead (O(n_back)).
  //
  // Use these for operations that push to the snapshot undo stack (addStitch,
  // paste, move, delete, etc.) where immutable snapshots must be preserved.
  //
  // For the 120 Hz draw hot-path (addStitchRaw, removeStitchRaw, etc.) use
  // the in-place variants below — they mutate [stitchesByCell] directly for
  // O(1) per call.

  /// Returns a new [Layer] with [stitch] appended.  O(N_cells).
  ///
  /// Does not check for duplicates; callers should guard with [stitchesAt].
  Layer withStitchAdded(Stitch stitch) {
    if (stitch is BackStitch) {
      return _copyFields(backstitches: [...backstitches, stitch]);
    }
    final c = stitch.cellCoords!;
    final existing = stitchesByCell[c] ?? const <Stitch>[];
    final newByCell = Map<Cell, List<Stitch>>.of(stitchesByCell);
    newByCell[c] = [...existing, stitch];
    return _copyFields(stitchesByCell: newByCell);
  }

  /// Returns a new [Layer] with any stitch geometrically equal to [stitch]
  /// removed from its cell, then [stitch] appended.  O(N_cells).
  ///
  /// Use when placing a stitch over an occupied cell (overwrite semantics).
  Layer withStitchReplaced(Stitch stitch) {
    if (stitch is BackStitch) {
      return _copyFields(backstitches: [
        ...backstitches.where((s) => s != stitch),
        stitch,
      ]);
    }
    final c = stitch.cellCoords!;
    final newByCell = Map<Cell, List<Stitch>>.of(stitchesByCell);
    final prev = newByCell[c] ?? const <Stitch>[];
    newByCell[c] = [...prev.where((s) => s != stitch), stitch];
    return _copyFields(stitchesByCell: newByCell);
  }

  /// Returns a new [Layer] with all existing stitches at the cell cleared and
  /// [stitch] placed as the sole occupant.  O(N_cells).
  ///
  /// Use when a FullStitch overwrites all partial stitches at the same cell.
  Layer withCellReplacedBy(Stitch stitch) {
    final c = stitch.cellCoords!;
    final newByCell = Map<Cell, List<Stitch>>.of(stitchesByCell);
    newByCell[c] = [stitch];
    return _copyFields(stitchesByCell: newByCell);
  }

  /// Returns a new [Layer] with overlapping stitches at the cell removed and
  /// [stitch] added. Non-overlapping stitches are preserved.  O(N_cells).
  Layer withOverlappingReplaced(Stitch stitch) {
    final c = stitch.cellCoords!;
    final newByCell = Map<Cell, List<Stitch>>.of(stitchesByCell);
    final prev = newByCell[c] ?? const <Stitch>[];
    newByCell[c] = [...prev.where((s) => !stitchesOverlap(s, stitch)), stitch];
    return _copyFields(stitchesByCell: newByCell);
  }

  /// Returns a new [Layer] with [stitch] removed.  O(N_cells) for cell stitches,
  /// O(n_back) for [BackStitch].  Returns `this` when [stitch] is not present.
  Layer withStitchRemoved(Stitch stitch) {
    if (stitch is BackStitch) {
      final newBack = backstitches.where((s) => s != stitch).toList();
      if (newBack.length == backstitches.length) return this;
      return _copyFields(backstitches: newBack);
    }
    final c = stitch.cellCoords;
    if (c == null) return this;
    final existing = stitchesByCell[c];
    if (existing == null) return this;
    final newList = existing.where((s) => s != stitch).toList();
    if (newList.length == existing.length) return this;
    final newByCell = Map<Cell, List<Stitch>>.of(stitchesByCell);
    if (newList.isEmpty) {
      newByCell.remove(c);
    } else {
      newByCell[c] = newList;
    }
    return _copyFields(stitchesByCell: newByCell);
  }

  /// Returns a new [Layer] with all stitches at cell ([x], [y]) removed, plus
  /// any [BackStitch] whose endpoint lies inside that cell.  O(N_cells).
  Layer withCellCleared(int x, int y) {
    final c = Cell(x, y);
    final hasCell = stitchesByCell.containsKey(c);
    final newBack = backstitches.where((s) => !_bsInCell(s, x, y)).toList();
    final hasBack = newBack.length < backstitches.length;
    if (!hasCell && !hasBack) return this;
    final newByCell = hasCell
        ? (Map<Cell, List<Stitch>>.of(stitchesByCell)..remove(c))
        : stitchesByCell;
    return _copyFields(stitchesByCell: newByCell, backstitches: newBack);
  }

  static bool _bsInCell(BackStitch s, int x, int y) {
    bool inside(double gx, double gy) =>
        gx >= x && gx <= x + 1 && gy >= y && gy <= y + 1;
    return inside(s.x1, s.y1) || inside(s.x2, s.y2);
  }

  // ── In-place mutation methods (120 Hz hot path) ──────────────────────────────
  //
  // Mutate [stitchesByCell] / [backstitches] directly and return `this`.
  // O(1) per call — no map copy.
  //
  // Safe ONLY when called via the UndoManager command path (addStitchRaw,
  // removeStitchRaw, etc.) where undo is handled by reversing commands,
  // not by snapshot restoration.  The snapshot undo stack never observes
  // partially-mutated maps because snapshot operations (addStitch, paste,
  // etc.) always create new Layer instances via the immutable methods above.

  /// Appends [stitch] in-place.  O(1).  Returns `this`.
  Layer addStitchInPlace(Stitch stitch) {
    if (stitch is BackStitch) {
      backstitches.add(stitch);
      return this;
    }
    final c = stitch.cellCoords!;
    final existing = stitchesByCell[c];
    if (existing != null) {
      existing.add(stitch);
    } else {
      stitchesByCell[c] = [stitch];
    }
    return this;
  }

  /// Removes stitch equal to [stitch] at its cell and appends [stitch].
  /// O(stitches_at_cell).  Returns `this`.
  Layer replaceStitchInPlace(Stitch stitch) {
    if (stitch is BackStitch) {
      backstitches.removeWhere((s) => s == stitch);
      backstitches.add(stitch);
      return this;
    }
    final c = stitch.cellCoords!;
    final existing = stitchesByCell[c];
    if (existing != null) {
      existing.removeWhere((s) => s == stitch);
      existing.add(stitch);
    } else {
      stitchesByCell[c] = [stitch];
    }
    return this;
  }

  /// Clears all stitches at the cell and places [stitch] as sole occupant.
  /// O(1).  Returns `this`.
  Layer replaceCellInPlace(Stitch stitch) {
    final c = stitch.cellCoords!;
    stitchesByCell[c] = [stitch];
    return this;
  }

  /// Removes overlapping stitches at the cell and adds [stitch].
  /// Non-overlapping stitches are preserved.  O(stitches_at_cell).
  Layer replaceOverlappingInPlace(Stitch stitch) {
    final c = stitch.cellCoords!;
    final existing = stitchesByCell[c];
    if (existing != null) {
      existing.removeWhere((s) => stitchesOverlap(s, stitch));
      existing.add(stitch);
    } else {
      stitchesByCell[c] = [stitch];
    }
    return this;
  }

  /// Removes [stitch] in-place.  O(stitches_at_cell).  Returns `this`.
  /// Returns `this` even when [stitch] was not present (no-op).
  Layer removeStitchInPlace(Stitch stitch) {
    if (stitch is BackStitch) {
      backstitches.removeWhere((s) => s == stitch);
      return this;
    }
    final c = stitch.cellCoords;
    if (c == null) return this;
    final existing = stitchesByCell[c];
    if (existing == null) return this;
    existing.removeWhere((s) => s == stitch);
    if (existing.isEmpty) stitchesByCell.remove(c);
    return this;
  }

  /// Removes all stitches at ([x], [y]) plus touching backstitches.  O(1).
  /// Returns `this`.
  Layer clearCellInPlace(int x, int y) {
    final c = Cell(x, y);
    stitchesByCell.remove(c);
    backstitches.removeWhere((s) => _bsInCell(s, x, y));
    return this;
  }

  // ── Bulk copyWith (non-hot path) ─────────────────────────────────────────────

  /// Returns a copy with the given fields replaced.
  ///
  /// When [stitches] is provided the cell index is rebuilt from it — O(N).
  /// For hot-path incremental updates prefer [withStitchAdded] etc.
  Layer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    LayerBlendMode? blendMode,
    List<Stitch>? stitches,
  }) {
    if (stitches != null) {
      final (:byCell, :back) = _indexList(stitches);
      return Layer._(
        id: id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        opacity: opacity ?? this.opacity,
        blendMode: blendMode ?? this.blendMode,
        stitchesByCell: byCell,
        backstitches: back,
      );
    }
    return Layer._(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      stitchesByCell: stitchesByCell,
      backstitches: backstitches,
    );
  }

  Layer _copyFields({
    Map<Cell, List<Stitch>>? stitchesByCell,
    List<BackStitch>? backstitches,
  }) =>
      Layer._(
        id: id,
        name: name,
        visible: visible,
        locked: locked,
        opacity: opacity,
        blendMode: blendMode,
        stitchesByCell: stitchesByCell ?? this.stitchesByCell,
        backstitches: backstitches ?? this.backstitches,
      );

  // ── Serialisation ────────────────────────────────────────────────────────────

  Map<String, dynamic> toYaml() => {
        'id': id,
        'name': name,
        'visible': visible,
        if (locked) 'locked': true,
        'opacity': opacity,
        if (blendMode != LayerBlendMode.normal) 'blendMode': blendMode.yamlKey,
        'stitches': stitches.map((s) => s.toYaml()).toList(),
      };

  factory Layer.fromYaml(Map<String, dynamic> yaml) {
    return Layer(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      visible: yaml['visible'] as bool? ?? true,
      locked: yaml['locked'] as bool? ?? false,
      opacity: (yaml['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: LayerBlendMode.fromYaml(yaml['blendMode'] as String?),
      stitches: Stitch.listFromYaml(yaml['stitches'] as List? ?? const []),
    );
  }
}
