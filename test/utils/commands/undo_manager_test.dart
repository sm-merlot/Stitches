import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/utils/commands/command.dart';
import 'package:stitches/utils/commands/undo_manager.dart';

// Simple command that records execute/undo calls for testing.
class _TrackingCommand extends Command {
  final List<String> log;
  final String name;

  const _TrackingCommand(this.log, this.name);

  @override
  void execute() => log.add('exec:$name');

  @override
  void undo() => log.add('undo:$name');
}

void main() {
  group('UndoManager', () {
    late UndoManager mgr;
    late List<String> log;

    setUp(() {
      mgr = UndoManager();
      log = [];
    });

    test('initial state: canUndo and canRedo are false', () {
      expect(mgr.canUndo, isFalse);
      expect(mgr.canRedo, isFalse);
    });

    test('initial counts are 0', () {
      expect(mgr.undoCount, 0);
      expect(mgr.redoCount, 0);
    });

    test('execute runs command and increments undoCount', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      expect(log, ['exec:A']);
      expect(mgr.canUndo, isTrue);
      expect(mgr.undoCount, 1);
    });

    test('undo calls undo on last command and moves it to redo stack', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.undo();
      expect(log, ['exec:A', 'undo:A']);
      expect(mgr.canUndo, isFalse);
      expect(mgr.canRedo, isTrue);
      expect(mgr.redoCount, 1);
    });

    test('redo re-executes undone command', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.undo();
      mgr.redo();
      expect(log, ['exec:A', 'undo:A', 'exec:A']);
      expect(mgr.canUndo, isTrue);
      expect(mgr.canRedo, isFalse);
    });

    test('undo is no-op when stack is empty', () {
      mgr.undo();
      expect(log, isEmpty);
    });

    test('redo is no-op when stack is empty', () {
      mgr.redo();
      expect(log, isEmpty);
    });

    test('execute clears redo stack', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.undo();
      expect(mgr.canRedo, isTrue);
      mgr.execute(_TrackingCommand(log, 'B'));
      expect(mgr.canRedo, isFalse);
      expect(mgr.redoCount, 0);
    });

    test('multiple commands undo in LIFO order', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.execute(_TrackingCommand(log, 'B'));
      mgr.execute(_TrackingCommand(log, 'C'));
      log.clear();
      mgr.undo();
      mgr.undo();
      expect(log, ['undo:C', 'undo:B']);
    });

    test('clear empties both stacks', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.undo();
      mgr.clear();
      expect(mgr.canUndo, isFalse);
      expect(mgr.canRedo, isFalse);
      expect(mgr.undoCount, 0);
      expect(mgr.redoCount, 0);
    });

    test('undo/redo cycle preserves command order', () {
      mgr.execute(_TrackingCommand(log, 'A'));
      mgr.execute(_TrackingCommand(log, 'B'));
      mgr.undo(); // undo B
      mgr.undo(); // undo A
      mgr.redo(); // redo A
      mgr.redo(); // redo B
      expect(log, [
        'exec:A', 'exec:B',
        'undo:B', 'undo:A',
        'exec:A', 'exec:B',
      ]);
    });
  });
}
