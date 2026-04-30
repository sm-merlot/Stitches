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
  /// Maximum number of undo entries kept.  Oldest entries are dropped first.
  static const int maxDepth = 200;

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
    if (_undoStack.length > maxDepth) _undoStack.removeAt(0);
    _redoStack.clear();
    onChange?.call();
  }

  /// Replaces the most recently pushed command with [cmd].
  ///
  /// No-op when the stack is empty. Clears the redo stack.
  /// Used by [StitchController] to squash a single-tap + flood-fill pair
  /// into one undo step: the flood fill replaces the prior single-tap entry,
  /// preserving the pre-tap [before] state so a single undo rolls back both.
  void replaceLast(Command cmd) {
    if (_undoStack.isEmpty) return;
    _undoStack[_undoStack.length - 1] = cmd;
    _redoStack.clear();
    onChange?.call();
  }

  /// Pushes [cmd] onto the undo stack WITHOUT calling [cmd.execute].
  ///
  /// Use when the mutation has already been applied by the notifier directly
  /// (e.g. commitPaste, floodFill) and we only need to record the inverse for
  /// later undo.  [cmd.execute] is still called on redo.
  void push(Command cmd) {
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
