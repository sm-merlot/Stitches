import 'command.dart';

/// Per-editing-context undo/redo stack.
///
/// One instance per mode controller:
/// - [EditController] owns one for pattern mutations.
/// - [StitchController] owns one for progress marks only.
/// - [SnippetEditController] owns one isolated from the parent pattern stack,
///   fixing the known bug where snippet edits bled into parent undo history.
///
/// [execute] runs the command and pushes it onto the undo stack, clearing
/// the redo stack (standard linear undo semantics).
///
/// Set [onChange] to a callback that is invoked after every [execute], [undo],
/// or [redo]. Typically wired to the notifier's `updateControllerUndoState`
/// so the toolbar reflects the live can-undo / can-redo state without the
/// caller needing a separate notification call after each operation.
class UndoManager {
  /// Called after every state-changing operation ([execute], [undo], [redo]).
  void Function()? onChange;

  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// For testing / diagnostics only.
  int get undoCount => _undoStack.length;

  /// For testing / diagnostics only.
  int get redoCount => _redoStack.length;

  /// Executes [cmd] and pushes it onto the undo stack.
  ///
  /// Clears the redo stack — branching redo is not supported.
  void execute(Command cmd) {
    cmd.execute();
    _undoStack.add(cmd);
    _redoStack.clear();
    onChange?.call();
  }

  /// Undoes the most recently executed command.  No-op when [canUndo] is false.
  void undo() {
    if (!canUndo) return;
    final cmd = _undoStack.removeLast();
    cmd.undo();
    _redoStack.add(cmd);
    onChange?.call();
  }

  /// Re-executes the most recently undone command.  No-op when [canRedo] is false.
  void redo() {
    if (!canRedo) return;
    final cmd = _redoStack.removeLast();
    cmd.execute();
    _undoStack.add(cmd);
    onChange?.call();
  }

  /// Clears both stacks.  Call when the pattern is replaced (file open / new).
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
