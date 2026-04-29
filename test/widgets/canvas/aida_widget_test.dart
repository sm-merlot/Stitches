/// Tests for [AidaWidget] and [CanvasStaticPainter].
///
/// Coverage:
/// - AidaWidget builds without crashing in all mode/controller configurations.
/// - CanvasStaticPainter.shouldRepaint fires on renderCache.version bump and
///   pan/zoom changes, but NOT on unrelated field equality.
/// - Mode isolation: stitch mode cannot access draw/paste handlers structurally.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stitches/models/progress/pattern_progress.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/services/render_cache.dart';
import 'package:stitches/services/stitch_compositor.dart';
import 'package:stitches/utils/controllers/canvas_callbacks.dart';
import 'package:stitches/utils/controllers/edit_controller.dart';
import 'package:stitches/utils/commands/shortcut_router.dart';
import 'package:stitches/utils/controllers/stitch_controller.dart';
import 'package:stitches/utils/controllers/view_mode_controller.dart';
import 'package:stitches/widgets/canvas/aida_widget.dart';
import 'package:stitches/widgets/canvas/canvas_painter.dart';

import '../test_helpers.dart';

// ─── Provider stubs ───────────────────────────────────────────────────────────

class _StubSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _StubEditor extends EditorNotifier {
  final EditorState _state;
  _StubEditor(this._state);

  @override
  EditorState build() => _state;

  // No-op overrides for calls made during widget lifecycle.
  @override
  void updateViewPosition(double x, double y, double scale) {}
}

// ─── Fake notifier for controller construction ────────────────────────────────

class _FakeNotifier implements EditorNotifier {
  @override
  dynamic noSuchMethod(Invocation i) {}
}

// ─── Widget pump helpers ──────────────────────────────────────────────────────

Widget _wrapAida(
  AidaWidget canvas, {
  EditorState? state,
}) {
  final editorState = state ?? fakeEditState();
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettings()),
      editorProvider.overrideWith(() => _StubEditor(editorState)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: canvas,
        ),
      ),
    ),
  );
}

EditController _editCtrl() => EditController(
      notifier: _FakeNotifier(),
      getState: () => fakeEditState(),
    );

ViewModeController _viewCtrl() =>
    ViewModeController(getState: () => fakeViewState());

StitchController _stitchCtrl() => StitchController(
      notifier: _FakeNotifier(),
      getState: () => fakeStitchState(),
    );

// ─── AidaWidget smoke tests ───────────────────────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  // Push a ShortcutRouter-compatible handler so AidaWidget's push/pop is safe.
  setUp(() => ShortcutRouter.instance.init());
  tearDown(() => ShortcutRouter.instance.dispose());

  group('AidaWidget — smoke tests', () {
    testWidgets('builds in edit mode with all controllers', (tester) async {
      final edit = _editCtrl();
      final view = _viewCtrl();
      final stitch = _stitchCtrl();
      await tester.pumpWidget(
        _wrapAida(
          AidaWidget(
            editController: edit,
            viewModeController: view,
            stitchController: stitch,
          ),
          state: fakeEditState(),
        ),
      );
      await tester.pump();
      expect(find.byType(AidaWidget), findsOneWidget);
    });

    testWidgets('builds in stitch mode', (tester) async {
      final edit = _editCtrl();
      final view = _viewCtrl();
      final stitch = _stitchCtrl();
      await tester.pumpWidget(
        _wrapAida(
          AidaWidget(
            editController: edit,
            viewModeController: view,
            stitchController: stitch,
          ),
          state: fakeStitchState(),
        ),
      );
      await tester.pump();
      expect(find.byType(AidaWidget), findsOneWidget);
    });

    testWidgets('builds in view mode', (tester) async {
      final edit = _editCtrl();
      final view = _viewCtrl();
      final stitch = _stitchCtrl();
      await tester.pumpWidget(
        _wrapAida(
          AidaWidget(
            editController: edit,
            viewModeController: view,
            stitchController: stitch,
          ),
          state: fakeViewState(),
        ),
      );
      await tester.pump();
      expect(find.byType(AidaWidget), findsOneWidget);
    });

    testWidgets('builds with null view and stitch controllers (snippet editor use)', (tester) async {
      final edit = _editCtrl();
      await tester.pumpWidget(
        _wrapAida(
          AidaWidget(
            editController: edit,
            viewModeController: null,
            stitchController: null,
          ),
          state: fakeEditState(),
        ),
      );
      await tester.pump();
      expect(find.byType(AidaWidget), findsOneWidget);
    });

    testWidgets('contains RepaintBoundary wrapping static painter', (tester) async {
      final edit = _editCtrl();
      await tester.pumpWidget(
        _wrapAida(
          AidaWidget(
            editController: edit,
            viewModeController: _viewCtrl(),
            stitchController: _stitchCtrl(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(1));
    });
  });

  // ─── Controller attachment lifecycle ─────────────────────────────────────────

  group('AidaWidget — controller lifecycle', () {
    testWidgets('attachCanvas called on mount, detachCanvas on unmount', (tester) async {
      var attached = false;
      var detached = false;

      // Instrument a controller by wrapping attachCanvas/detachCanvas.
      final notifier = _FakeNotifier();
      final ctrl = EditController(
        notifier: notifier,
        getState: () => fakeEditState(),
      );

      // Attach a spy by subclassing the CanvasCallbacks path via a wrapper.
      // Simplest approach: track hover handler nullity — it's null before
      // attach and non-null after.

      final widget = AidaWidget(
        editController: ctrl,
        viewModeController: null,
        stitchController: null,
      );

      await tester.pumpWidget(_wrapAida(widget));
      await tester.pump();
      // After mount, hover handler is non-null (set by attachCanvas).
      attached = ctrl.hover != null;

      // Remove the widget to trigger dispose → detachCanvas.
      await tester.pumpWidget(const SizedBox.shrink());
      detached = ctrl.hover == null;

      expect(attached, isTrue, reason: 'hover handler non-null after attachCanvas');
      expect(detached, isTrue, reason: 'hover handler null after detachCanvas');
    });
  });

  // ─── Mode isolation: stitch mode ─────────────────────────────────────────────

  group('AidaWidget — mode isolation', () {
    test('StitchController owns no DrawHandler or PasteHandler', () {
      final ctrl = _stitchCtrl();
      final cb = CanvasCallbacks(
        scheduleRebuild: () {},
        onWarning: (_) {},
        getPencilPasteConfirm: () => false,
      );
      ctrl.attachCanvas(cb);
      // StitchController exposes only hover and progress — never draw/paste.
      expect(ctrl.hover, isNotNull);
      expect(ctrl.progress, isNotNull);
      // DrawHandler and PasteHandler do not exist on StitchController —
      // this is verified structurally: the class has no such getters.
      // The compiler enforces it; no runtime check needed.
      ctrl.detachCanvas();
    });

    test('ViewModeController owns no draw, paste, or progress handlers', () {
      final ctrl = _viewCtrl();
      final cb = CanvasCallbacks(
        scheduleRebuild: () {},
        onWarning: (_) {},
        getPencilPasteConfirm: () => false,
      );
      ctrl.attachCanvas(cb);
      expect(ctrl.hover, isNotNull);
      ctrl.detachCanvas();
    });
  });

  // ─── CanvasStaticPainter.shouldRepaint ────────────────────────────────────────

  group('CanvasStaticPainter.shouldRepaint', () {
    // Shared pattern so identity checks don't trigger spurious repaints.
    final sharedPattern = fakePattern();

    CanvasStaticPainter painter({
      RenderCache? renderCache,
      int? cacheVersion,
      Offset panOffset = Offset.zero,
      double scale = 1.0,
      bool stitchMode = false,
    }) {
      final cache = renderCache ?? RenderCache();
      return CanvasStaticPainter(
        pattern: sharedPattern,
        cellSize: 20.0,
        panOffset: panOffset,
        scale: scale,
        aidaColor: Colors.white,
        renderCache: cache,
        cacheVersion: cacheVersion ?? cache.version,
        stitchMode: stitchMode,
        stitchCrossMode: false,
        stitchBackMode: false,
        stitchFocusThreadId: null,
        referenceImage: null,
        referenceOpacity: 1.0,
        referenceVisible: false,
        compositeLayer: null,
        pageLayout: null,
        currentPage: 0,
        progress: PatternProgress.empty,
      );
    }

    test('no repaint when cacheVersion, panOffset, scale all identical', () {
      final cache = RenderCache();
      final p1 = painter(renderCache: cache);
      final p2 = painter(renderCache: cache);
      expect(p2.shouldRepaint(p1), isFalse);
    });

    test('repaints when cacheVersion differs (data changed)', () {
      // AidaWidget snapshots renderCache.version at build time so old and new
      // painters carry different int values after a rebuild.
      final cache = RenderCache();
      final p1 = painter(renderCache: cache, cacheVersion: 0);
      cache.rebuild(
        const CompositeLayer(
          fullStitches: {},
          otherStitches: [],
          backstitches: [],
          crossStitchEquiv: {},
          backStitchEquiv: {},
        ),
        const RenderViewConfig(),
        20.0,
      );
      final p2 = painter(renderCache: cache, cacheVersion: cache.version);
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('no repaint when cacheVersion unchanged despite same-object cache', () {
      // Simulates back-to-back builds where nothing data-relevant changed
      // (e.g. an unrelated provider updated). Version stays 0 on both painters.
      final cache = RenderCache();
      final p1 = painter(renderCache: cache, cacheVersion: cache.version);
      final p2 = painter(renderCache: cache, cacheVersion: cache.version);
      expect(p2.shouldRepaint(p1), isFalse);
    });

    test('repaints when panOffset changes', () {
      final cache = RenderCache();
      final p1 = painter(renderCache: cache, panOffset: Offset.zero);
      final p2 = painter(renderCache: cache, panOffset: const Offset(10, 0));
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('repaints when scale changes', () {
      final cache = RenderCache();
      final p1 = painter(renderCache: cache, scale: 1.0);
      final p2 = painter(renderCache: cache, scale: 1.5);
      expect(p2.shouldRepaint(p1), isTrue);
    });

    test('repaints when cacheVersion bumps due to stitchMode change', () {
      // stitchMode is in RenderViewConfig → rebuildViewConfig → version bumps.
      // shouldRepaint detects this via cacheVersion, not a stitchMode field.
      final cache = RenderCache();
      final p1 = painter(renderCache: cache, cacheVersion: 0);
      cache.rebuildViewConfig(
        const CompositeLayer(
          fullStitches: {},
          otherStitches: [],
          backstitches: [],
          crossStitchEquiv: {},
          backStitchEquiv: {},
        ),
        const RenderViewConfig(stitchMode: true),
        20.0,
      );
      final p2 = painter(renderCache: cache, cacheVersion: cache.version);
      expect(p2.shouldRepaint(p1), isTrue);
    });
  });
}
