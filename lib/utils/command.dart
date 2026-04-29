import '../models/stitch.dart';
import '../providers/editor/editor_provider.dart';

/// A reversible operation.
///
/// Produced by mutating editor operations; stored in an [UndoManager] stack.
/// [execute] and [undo] must be exact inverses of each other.
///
/// Commands call raw notifier variants (e.g. [EditorNotifier.addStitchRaw])
/// that mutate state without touching the snapshot undo stack.
abstract class Command {
  const Command();

  /// Applies the operation.
  void execute();

  /// Reverses the operation.
  void undo();
}

// ─── Draw commands ────────────────────────────────────────────────────────────

/// Adds a single stitch to the active layer.
///
/// [overwritten] is the list of stitches removed from the layer when [stitch]
/// was placed (captured by the controller before calling [execute]).
/// [undo] removes [stitch] and restores [overwritten].
class AddStitchCommand implements Command {
  AddStitchCommand({
    required this.notifier,
    required this.stitch,
    required this.overwritten,
  });

  final EditorNotifier notifier;
  final Stitch stitch;

  /// Stitches displaced by placing [stitch] (same cell + type, different thread).
  final List<Stitch> overwritten;

  @override
  void execute() => notifier.addStitchRaw(stitch);

  @override
  void undo() {
    notifier.removeStitchRaw(stitch);
    for (final s in overwritten) {
      notifier.addStitchRaw(s);
    }
  }
}

/// Removes all stitches touching a single cell.
///
/// [removed] is captured before [execute] so [undo] can restore them exactly.
class RemoveStitchesAtCommand implements Command {
  RemoveStitchesAtCommand({
    required this.notifier,
    required this.x,
    required this.y,
    required this.removed,
  });

  final EditorNotifier notifier;
  final int x;
  final int y;
  final List<Stitch> removed;

  @override
  void execute() => notifier.removeStitchesAtRaw(x, y);

  @override
  void undo() {
    for (final s in removed) {
      notifier.addStitchRaw(s);
    }
  }
}

/// Removes all stitches in a [size]×[size] box centred on (cx, cy).
///
/// [removed] is captured before [execute] so [undo] can restore them exactly.
class RemoveStitchesInBoxCommand implements Command {
  RemoveStitchesInBoxCommand({
    required this.notifier,
    required this.cx,
    required this.cy,
    required this.size,
    required this.removed,
  });

  final EditorNotifier notifier;
  final int cx;
  final int cy;
  final int size;
  final List<Stitch> removed;

  @override
  void execute() => notifier.removeStitchesInBoxRaw(cx, cy, size);

  @override
  void undo() {
    for (final s in removed) {
      notifier.addStitchRaw(s);
    }
  }
}
