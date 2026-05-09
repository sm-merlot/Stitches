import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stitches/models/pattern.dart';
import 'package:stitches/providers/editor/editor_provider.dart';
import 'package:stitches/providers/settings_provider.dart';
import 'package:stitches/providers/stitching_timer_provider.dart';
import 'package:stitches/services/editor_session_service.dart';

// ─── Controllable timer notifier ─────────────────────────────────────────────

/// Subclass that lets tests supply an arbitrary [DateTime] for "now".
class _FakeTimerNotifier extends StitchingTimerNotifier {
  _FakeTimerNotifier(DateTime Function() nowFn) : _nowFn = nowFn;

  final DateTime Function() _nowFn;

  @override
  DateTime now() => _nowFn();
}

// ─── Container helpers ───────────────────────────────────────────────────────

class _StubSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

ProviderContainer _makeContainer(DateTime Function() nowFn) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _StubSettingsNotifier()),
      stitchingTimerProvider.overrideWith(() => _FakeTimerNotifier(nowFn)),
    ],
  );
}

void _loadEmpty(ProviderContainer c) {
  final pattern = CrossStitchPattern.empty(name: 'Test');
  c.read(editorProvider.notifier).loadPattern(
    pattern,
    session: EditorSession(selectedThreadId: pattern.editorSelectedThreadId),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StitchingTimerNotifier — same-day session', () {
    late DateTime Function() nowFn;
    late ProviderContainer c;

    setUp(() {
      // Default "now" — tests can reassign nowFn between start and stop.
      nowFn = DateTime.now;
      c = _makeContainer(() => nowFn());
      _loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('stop after 45-minute same-day session logs 45 minutes to today', () {
      final sessionStart = DateTime(2026, 4, 29, 10, 0, 0); // 10:00 AM
      nowFn = () => sessionStart;

      // Manually inject the session start so we bypass start()'s async prefs write.
      final timerNotifier = c.read(stitchingTimerProvider.notifier);
      c.read(stitchingTimerProvider.notifier).state =
          StitchingTimerState(sessions: {kTimerStandaloneKey: TimerSession(isRunning: true, sessionStart: sessionStart)});

      // Advance "now" to 45 minutes later and stop.
      final stopTime = DateTime(2026, 4, 29, 10, 45, 0);
      nowFn = () => stopTime;
      timerNotifier.stop();

      final log = c.read(editorProvider).pattern.progressLog;
      expect(log, hasLength(1));
      expect(log.first.isoDate, equals('2026-04-29'));
      expect(log.first.minutesSpent, equals(45));
    });

    test('stop() returns 0 and logs nothing for sub-minute sessions', () {
      final sessionStart = DateTime(2026, 4, 29, 10, 0, 0);
      c.read(stitchingTimerProvider.notifier).state =
          StitchingTimerState(sessions: {kTimerStandaloneKey: TimerSession(isRunning: true, sessionStart: sessionStart)});

      // Only 30 seconds elapsed — inMinutes truncates to 0.
      nowFn = () => sessionStart.add(const Duration(seconds: 30));
      final minutes = c.read(stitchingTimerProvider.notifier).stop();

      expect(minutes, equals(0));
      expect(c.read(editorProvider).pattern.progressLog, isEmpty);
    });
  });

  // ─── Bug 5: midnight crossing ───────────────────────────────────────────────

  group('StitchingTimerNotifier — midnight crossing (Bug 5)', () {
    late DateTime Function() nowFn;
    late ProviderContainer c;

    setUp(() {
      nowFn = DateTime.now;
      c = _makeContainer(() => nowFn());
      _loadEmpty(c);
    });
    tearDown(() => c.dispose());

    test('session spanning midnight splits minutes at day boundary', () {
      // Session: 2026-04-28 23:30 → 2026-04-29 00:15 (45 min total)
      // Expected: 30 min to 2026-04-28, 15 min to 2026-04-29
      final sessionStart = DateTime(2026, 4, 28, 23, 30, 0);
      final stopTime = DateTime(2026, 4, 29, 0, 15, 0);

      c.read(stitchingTimerProvider.notifier).state =
          StitchingTimerState(sessions: {kTimerStandaloneKey: TimerSession(isRunning: true, sessionStart: sessionStart)});
      nowFn = () => stopTime;

      final totalMinutes = c.read(stitchingTimerProvider.notifier).stop();

      expect(totalMinutes, equals(45));

      final log = c.read(editorProvider).pattern.progressLog;
      expect(log, hasLength(2));

      final prevDay = log.firstWhere((e) => e.isoDate == '2026-04-28');
      final today = log.firstWhere((e) => e.isoDate == '2026-04-29');
      expect(prevDay.minutesSpent, equals(30));
      expect(today.minutesSpent, equals(15));
    });

    test('session ending exactly at midnight attributes all minutes to previous day', () {
      // 2026-04-28 23:00 → 2026-04-29 00:00 (60 min, stops at midnight)
      // Expected: 60 min to 2026-04-28, nothing for 2026-04-29
      final sessionStart = DateTime(2026, 4, 28, 23, 0, 0);
      final stopTime = DateTime(2026, 4, 29, 0, 0, 0); // exact midnight

      c.read(stitchingTimerProvider.notifier).state =
          StitchingTimerState(sessions: {kTimerStandaloneKey: TimerSession(isRunning: true, sessionStart: sessionStart)});
      nowFn = () => stopTime;

      c.read(stitchingTimerProvider.notifier).stop();

      final log = c.read(editorProvider).pattern.progressLog;
      // Today's portion is 0 minutes, so no entry for 2026-04-29.
      final prevDay = log.firstWhere((e) => e.isoDate == '2026-04-28');
      expect(prevDay.minutesSpent, equals(60));
      expect(log.any((e) => e.isoDate == '2026-04-29'), isFalse);
    });

    test('session starting exactly at midnight logs all minutes to the new day', () {
      // 2026-04-29 00:00 → 2026-04-29 00:30 (same day, no split)
      final sessionStart = DateTime(2026, 4, 29, 0, 0, 0);
      final stopTime = DateTime(2026, 4, 29, 0, 30, 0);

      c.read(stitchingTimerProvider.notifier).state =
          StitchingTimerState(sessions: {kTimerStandaloneKey: TimerSession(isRunning: true, sessionStart: sessionStart)});
      nowFn = () => stopTime;

      c.read(stitchingTimerProvider.notifier).stop();

      final log = c.read(editorProvider).pattern.progressLog;
      expect(log, hasLength(1));
      expect(log.first.isoDate, equals('2026-04-29'));
      expect(log.first.minutesSpent, equals(30));
    });
  });
}
