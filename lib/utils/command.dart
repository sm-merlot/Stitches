/// A reversible operation.
///
/// Produced by mutating editor operations; stored in an [UndoManager] stack.
/// [execute] and [undo] must be exact inverses of each other.
///
/// Commands do not own UI or Riverpod state — they receive the minimal
/// callbacks needed to mutate data and update the compositor.
abstract class Command {
  const Command();

  /// Applies the operation.
  void execute();

  /// Reverses the operation.
  void undo();
}
