/// Integration smoke tests for the four core editor flows.
///
/// These tests exercise the full stack end-to-end:
///   EditorNotifier → FileService (real disk I/O) → round-trip parse
///
/// They live in integration_test/ so they can be run against a real desktop
/// device with `flutter test integration_test/` during the v1 release
/// checklist. They are **not** wired to pre-commit CI — see the CI wiring
/// note in test-coverage.md.
///
/// Run locally:
///   flutter test integration_test/editor_flows_test.dart -d macos
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/cell.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/models/stitch.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/editor_session_service.dart';
import 'package:stitches/services/file_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _StubSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

ProviderContainer _makeContainer() => ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => _StubSettings())],
    );

EditorNotifier _notifier(ProviderContainer c) =>
    c.read(editorProvider.notifier);
EditorState _state(ProviderContainer c) => c.read(editorProvider);

void _loadEmpty(ProviderContainer c, {String name = 'Test'}) {
  final pat = CrossStitchPattern.empty(name: name);
  _notifier(c).loadPattern(pat,
      session: EditorSession(selectedThreadId: pat.editorSelectedThreadId));
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final base = await getTemporaryDirectory();
    tmpDir = await Directory(
            p.join(base.path,
                'stitches_integration_${DateTime.now().millisecondsSinceEpoch}'))
        .create();
  });

  tearDownAll(() async {
    await tmpDir.delete(recursive: true);
  });

  // ── Flow 1: draw → save → reload → verify stitches ───────────────────────

  testWidgets(
      'Flow 1: draw stitches, save, reload — stitches survive round-trip',
      (tester) async {
    final c = _makeContainer();
    addTearDown(c.dispose);
    _loadEmpty(c, name: 'Flow1');

    _notifier(c).setMode(AppMode.edit);
    // addStitch auto-adds the thread to the palette.
    _notifier(c).addStitch(const FullStitch(x: 2, y: 3, threadId: '310'));
    _notifier(c).addStitch(const FullStitch(x: 4, y: 5, threadId: '310'));
    _notifier(c).addStitch(
        const BackStitch(x1: 0, y1: 0, x2: 1, y2: 1, threadId: '310'));

    expect(_state(c).pattern.stitches, hasLength(3));
    expect(_state(c).isDirty, isTrue);

    final filePath = p.join(tmpDir.path, 'flow1.stitches');
    await FileService.saveFile(_state(c).pattern, filePath, compress: false);
    expect(await File(filePath).exists(), isTrue);

    final c2 = _makeContainer();
    addTearDown(c2.dispose);
    final (loaded, _, _) = await FileService.openFileFromPath(filePath);
    _notifier(c2).loadPattern(loaded,
        filePath: filePath,
        session:
            EditorSession(selectedThreadId: loaded.editorSelectedThreadId));

    final stitches = _state(c2).pattern.stitches;
    expect(stitches.whereType<FullStitch>(), hasLength(2));
    expect(stitches.whereType<BackStitch>(), hasLength(1));
    expect(_state(c2).isDirty, isFalse);
    expect(
        stitches.whereType<FullStitch>().any((s) => s.x == 2 && s.y == 3),
        isTrue);
  });

  // ── Flow 2: select → copy → paste at offset → undo ───────────────────────

  testWidgets(
      'Flow 2: copy/paste round-trip and undo restores original state',
      (tester) async {
    final c = _makeContainer();
    addTearDown(c.dispose);
    _loadEmpty(c, name: 'Flow2');

    _notifier(c).setMode(AppMode.edit);
    _notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
    _notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));

    _notifier(c).setSelectionRect(const Rect.fromLTRB(0, 0, 4, 4));
    await _notifier(c).copySelection();
    expect(_state(c).clipboard, isNotNull);
    expect(_state(c).drawingMode, equals(DrawingMode.paste));

    _notifier(c).commitPaste(5, 5);

    final afterPaste = _state(c).pattern.stitches.whereType<FullStitch>();
    expect(afterPaste.any((s) => s.x == 5 && s.y == 5), isTrue);
    expect(afterPaste, hasLength(4));

    _notifier(c).undo();
    final afterUndo = _state(c).pattern.stitches.whereType<FullStitch>();
    expect(afterUndo, hasLength(2));
    expect(afterUndo.any((s) => s.x == 5), isFalse);
  });

  // ── Flow 3: stitch mode progress → save → reload → verify ────────────────

  testWidgets(
      'Flow 3: mark region done, save, reload — progress persists',
      (tester) async {
    final c = _makeContainer();
    addTearDown(c.dispose);
    _loadEmpty(c, name: 'Flow3');

    _notifier(c).setMode(AppMode.edit);
    for (var x = 0; x < 2; x++) {
      for (var y = 0; y < 2; y++) {
        _notifier(c).addStitch(FullStitch(x: x, y: y, threadId: '310'));
      }
    }

    _notifier(c).setMode(AppMode.stitch);
    _notifier(c).markRegionDone(const Rect.fromLTRB(0, 0, 2, 2));
    expect(
        _state(c).pattern.progress.completedStitches, hasLength(4));

    final filePath = p.join(tmpDir.path, 'flow3.stitches');
    await FileService.saveFile(_state(c).pattern, filePath, compress: false);

    final c2 = _makeContainer();
    addTearDown(c2.dispose);
    final (loaded, _, _) = await FileService.openFileFromPath(filePath);
    _notifier(c2).loadPattern(loaded,
        filePath: filePath,
        session:
            EditorSession(selectedThreadId: loaded.editorSelectedThreadId));

    expect(
        _state(c2).pattern.progress.completedStitches, hasLength(4));
    expect(
        _state(c2)
            .pattern
            .progress
            .completedStitches
            .any((s) => s == const Cell(0, 0)),
        isTrue);
  });

  // ── Flow 4: snippet save → pattern save → reload → verify snippet ────────

  testWidgets(
      'Flow 4: snippet round-trip — create, save, reload, verify',
      (tester) async {
    final c = _makeContainer();
    addTearDown(c.dispose);
    _loadEmpty(c, name: 'Flow4');

    _notifier(c).setMode(AppMode.edit);
    _notifier(c).addStitch(const FullStitch(x: 0, y: 0, threadId: '310'));
    _notifier(c).addStitch(const FullStitch(x: 1, y: 0, threadId: '310'));

    _notifier(c).setSelectionRect(const Rect.fromLTRB(0, 0, 2, 1));
    final saved = _notifier(c).saveSelectionAsSnippet('My Motif');
    expect(saved, isTrue);
    expect(_state(c).pattern.snippets, hasLength(1));
    final snippetId = _state(c).pattern.snippets.single.id;

    final filePath = p.join(tmpDir.path, 'flow4.stitches');
    await FileService.saveFile(_state(c).pattern, filePath, compress: false);

    final c2 = _makeContainer();
    addTearDown(c2.dispose);
    final (loaded, _, _) = await FileService.openFileFromPath(filePath);
    _notifier(c2).loadPattern(loaded,
        filePath: filePath,
        session:
            EditorSession(selectedThreadId: loaded.editorSelectedThreadId));

    expect(_state(c2).pattern.snippets, hasLength(1));
    expect(_state(c2).pattern.snippets.single.id, equals(snippetId));
    expect(_state(c2).pattern.snippets.single.name, equals('My Motif'));
    expect(
        _state(c2).pattern.snippets.single.stitches.whereType<FullStitch>(),
        hasLength(2));
  });
}

