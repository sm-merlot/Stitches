import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch/stitch.dart';
import 'package:stitches/models/stitch/stitch_geometry.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';
import 'package:stitches/utils/commands/command.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

ProviderContainer makeContainer() {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettings()),
    ],
  );
}

class _StubSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

EditorNotifier notifier(ProviderContainer c) => c.read(editorProvider.notifier);
EditorState editorState(ProviderContainer c) => c.read(editorProvider);

void loadEmpty(ProviderContainer c) {
  final pattern = CrossStitchPattern.empty(name: 'Test');
  notifier(c).loadPattern(
    pattern,
    session: EditorSession(selectedThreadId: pattern.editorSelectedThreadId),
  );
}

List<Stitch> stitches(ProviderContainer c) =>
    editorState(c).activeLayer.stitches;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AddStitchCommand', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('execute adds stitch to layer', () {
      const stitch = FullStitch(x: 2, y: 3, threadId: '310');
      final cmd = AddStitchCommand(
        notifier: notifier(c),
        stitch: stitch,
        overwritten: [],
      );
      cmd.execute();
      expect(
        stitches(c).whereType<FullStitch>().any((s) => s.x == 2 && s.y == 3),
        isTrue,
      );
    });

    test('undo removes the added stitch', () {
      const stitch = FullStitch(x: 2, y: 3, threadId: '310');
      final cmd = AddStitchCommand(
        notifier: notifier(c),
        stitch: stitch,
        overwritten: [],
      );
      cmd.execute();
      expect(stitches(c).whereType<FullStitch>(), hasLength(1));

      cmd.undo();
      expect(stitches(c).whereType<FullStitch>(), isEmpty);
    });

    test('undo restores overwritten stitch', () {
      // Place a red stitch, then overwrite with black.
      notifier(c).addStitch(const FullStitch(x: 1, y: 1, threadId: '666'));
      final overwritten =
          stitches(c).where((s) => s == const FullStitch(x: 1, y: 1, threadId: '666')).toList();

      const newStitch = FullStitch(x: 1, y: 1, threadId: '310');
      final cmd = AddStitchCommand(
        notifier: notifier(c),
        stitch: newStitch,
        overwritten: overwritten,
      );
      cmd.execute();
      // After execute: black stitch at (1,1).
      expect(
        stitches(c).whereType<FullStitch>().single.threadId,
        '310',
      );

      cmd.undo();
      // After undo: red stitch restored.
      expect(
        stitches(c).whereType<FullStitch>().single.threadId,
        '666',
      );
    });

    test('execute does not push to snapshot stack — canUndo stays false without delegate', () {
      // No snapshot entries and no delegate → canUndo is false.
      expect(editorState(c).canUndo, isFalse);
      AddStitchCommand(
          notifier: notifier(c),
          stitch: const FullStitch(x: 0, y: 0, threadId: '310'),
          overwritten: []).execute();
      // canUndo still false: raw add does not push snapshot.
      expect(editorState(c).canUndo, isFalse);
    });

    test('two executes then two undos round-trips to empty', () {
      const s1 = FullStitch(x: 0, y: 0, threadId: '310');
      const s2 = FullStitch(x: 1, y: 0, threadId: '310');
      final cmd1 =
          AddStitchCommand(notifier: notifier(c), stitch: s1, overwritten: []);
      final cmd2 =
          AddStitchCommand(notifier: notifier(c), stitch: s2, overwritten: []);
      cmd1.execute();
      cmd2.execute();
      expect(stitches(c).whereType<FullStitch>(), hasLength(2));

      cmd2.undo();
      expect(stitches(c).whereType<FullStitch>(), hasLength(1));
      cmd1.undo();
      expect(stitches(c).whereType<FullStitch>(), isEmpty);
    });
  });

  group('RemoveStitchesAtCommand', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('execute removes stitches at cell', () {
      notifier(c).addStitch(const FullStitch(x: 3, y: 4, threadId: '310'));
      final removed = List<Stitch>.from(stitches(c));

      RemoveStitchesAtCommand(
        notifier: notifier(c),
        x: 3,
        y: 4,
        removed: removed,
      ).execute();

      expect(stitches(c).whereType<FullStitch>(), isEmpty);
    });

    test('undo restores removed stitches', () {
      notifier(c).addStitch(const FullStitch(x: 3, y: 4, threadId: '310'));
      final removed = List<Stitch>.from(stitches(c));

      final cmd = RemoveStitchesAtCommand(
        notifier: notifier(c),
        x: 3,
        y: 4,
        removed: removed,
      );
      cmd.execute();
      expect(stitches(c).whereType<FullStitch>(), isEmpty);

      cmd.undo();
      expect(
        stitches(c).whereType<FullStitch>().any((s) => s.x == 3 && s.y == 4),
        isTrue,
      );
    });

    test('execute does not push to snapshot stack — canUndo stays false without delegate', () {
      // Raw add (via AddStitchCommand) to set up something to remove.
      AddStitchCommand(
          notifier: notifier(c),
          stitch: const FullStitch(x: 0, y: 0, threadId: '310'),
          overwritten: []).execute();
      expect(editorState(c).canUndo, isFalse); // raw add did not push

      final removed = List<Stitch>.from(stitches(c));
      RemoveStitchesAtCommand(
        notifier: notifier(c),
        x: 0,
        y: 0,
        removed: removed,
      ).execute();
      // raw remove also did not push.
      expect(editorState(c).canUndo, isFalse);
    });
  });

  group('RemoveStitchesInBoxCommand', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('execute removes all stitches in box', () {
      notifier(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 3, y: 3, threadId: '310'));
      notifier(c).addStitch(const FullStitch(x: 9, y: 9, threadId: '310'));
      final removed = stitches(c)
          .where((s) {
            final coords = s.cellCoords;
            if (coords == null) return false;
            return coords.x >= 1 && coords.x <= 3 &&
                coords.y >= 1 && coords.y <= 3;
          })
          .toList();

      RemoveStitchesInBoxCommand(
        notifier: notifier(c),
        cx: 2,
        cy: 2,
        size: 3,
        removed: removed,
      ).execute();

      // (9,9) should survive; (2,2) and (3,3) removed.
      expect(stitches(c).whereType<FullStitch>(), hasLength(1));
      expect(stitches(c).whereType<FullStitch>().single.x, 9);
    });

    test('undo restores removed stitches', () {
      notifier(c).addStitch(const FullStitch(x: 2, y: 2, threadId: '310'));
      final removed = List<Stitch>.from(stitches(c));

      final cmd = RemoveStitchesInBoxCommand(
        notifier: notifier(c),
        cx: 2,
        cy: 2,
        size: 1,
        removed: removed,
      );
      cmd.execute();
      expect(stitches(c).whereType<FullStitch>(), isEmpty);

      cmd.undo();
      expect(
        stitches(c).whereType<FullStitch>().any((s) => s.x == 2 && s.y == 2),
        isTrue,
      );
    });
  });

  group('EditorNotifier — delegate routing', () {
    late ProviderContainer c;
    setUp(() {
      c = makeContainer();
      loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('controllerCanUndo false before delegate registered', () {
      expect(editorState(c).controllerCanUndo, isFalse);
    });

    test('updateControllerUndoState reflects canUndo from delegate', () {
      var fakeCanUndo = false;
      notifier(c).registerUndoDelegate(
        canUndo: () => fakeCanUndo,
        canRedo: () => false,
        undo: () {},
        redo: () {},
      );
      notifier(c).updateControllerUndoState();
      expect(editorState(c).controllerCanUndo, isFalse);

      fakeCanUndo = true;
      notifier(c).updateControllerUndoState();
      expect(editorState(c).controllerCanUndo, isTrue);
    });

    test('unregisterUndoDelegate + updateControllerUndoState resets controllerCanUndo', () {
      notifier(c).registerUndoDelegate(
        canUndo: () => true,
        canRedo: () => true,
        undo: () {},
        redo: () {},
      );
      notifier(c).updateControllerUndoState(); // reflect registered delegate
      expect(editorState(c).controllerCanUndo, isTrue);

      // After unregistering, manually refresh — no delegate → both false.
      notifier(c).unregisterUndoDelegate();
      notifier(c).updateControllerUndoState();
      expect(editorState(c).controllerCanUndo, isFalse);
    });

    test('notifier.undo() routes through delegate when it canUndo', () {
      var undoCalled = false;
      notifier(c).registerUndoDelegate(
        canUndo: () => true,
        canRedo: () => false,
        undo: () => undoCalled = true,
        redo: () {},
      );
      notifier(c).updateControllerUndoState();
      notifier(c).undo();
      expect(undoCalled, isTrue);
    });

    test('notifier.undo() falls through to snapshot stack when delegate empty', () {
      // Push something to snapshot stack via a full addStitch.
      notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
      expect(stitches(c).whereType<FullStitch>(), hasLength(1));

      // Register delegate that says it cannot undo.
      notifier(c).registerUndoDelegate(
        canUndo: () => false,
        canRedo: () => false,
        undo: () {},
        redo: () {},
      );
      notifier(c).updateControllerUndoState();

      // notifier.undo() should fall through to snapshot undo.
      notifier(c).undo();
      expect(stitches(c).whereType<FullStitch>(), isEmpty);
    });
  });
}

