import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'editor/editor_provider.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kSessionStartKey = 'stitching_timer_session_start_ms';

// ─── State ────────────────────────────────────────────────────────────────────

class StitchingTimerState {
  /// Whether a session is currently running.
  final bool isRunning;

  /// When the current session started (null when not running).
  final DateTime? sessionStart;

  /// Increments every second while running — drives widget rebuilds.
  final int tickCount;

  const StitchingTimerState({
    this.isRunning = false,
    this.sessionStart,
    this.tickCount = 0,
  });

  /// Elapsed duration of the current session (0 if not running).
  Duration get elapsed =>
      isRunning && sessionStart != null
          ? DateTime.now().difference(sessionStart!)
          : Duration.zero;

  StitchingTimerState copyWith({
    bool? isRunning,
    DateTime? sessionStart,
    bool clearSessionStart = false,
    int? tickCount,
  }) =>
      StitchingTimerState(
        isRunning: isRunning ?? this.isRunning,
        sessionStart:
            clearSessionStart ? null : (sessionStart ?? this.sessionStart),
        tickCount: tickCount ?? this.tickCount,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class StitchingTimerNotifier extends Notifier<StitchingTimerState> {
  Timer? _ticker;

  @override
  StitchingTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    // Restore any session that was running when the app was last killed.
    _restorePersistedSession();
    return const StitchingTimerState();
  }

  /// Reads SharedPreferences synchronously-ish: fires an async check and
  /// updates state if a persisted session is found.
  Future<void> _restorePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kSessionStartKey);
    if (ms == null) return;
    final savedStart = DateTime.fromMillisecondsSinceEpoch(ms);
    // Sanity check: ignore sessions older than 24 hours (likely a stale entry).
    if (DateTime.now().difference(savedStart).inHours > 24) {
      await prefs.remove(_kSessionStartKey);
      return;
    }
    // Resume the session.
    state = StitchingTimerState(
      isRunning: true,
      sessionStart: savedStart,
      tickCount: 0,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(tickCount: state.tickCount + 1);
    });
  }

  /// Start the timer. No-op if already running.
  void start() async {
    if (state.isRunning) return;
    final now = DateTime.now();
    // Persist the session start time before updating state so a kill between
    // the two operations still recovers the session on next launch.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSessionStartKey, now.millisecondsSinceEpoch);
    state = state.copyWith(
      isRunning: true,
      sessionStart: now,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(tickCount: state.tickCount + 1);
    });
  }

  /// Stop the timer and persist elapsed minutes to today's progress log.
  ///
  /// Returns the number of whole minutes recorded (may be 0 for very short
  /// sessions — those seconds are silently discarded).
  int stop() {
    if (!state.isRunning) return 0;
    _ticker?.cancel();
    _ticker = null;

    final elapsed = state.elapsed;
    final minutes = elapsed.inMinutes;

    state = state.copyWith(
      isRunning: false,
      clearSessionStart: true,
      tickCount: 0,
    );

    // Clear the persisted session start (fire-and-forget is fine here).
    SharedPreferences.getInstance()
        .then((p) => p.remove(_kSessionStartKey));

    if (minutes > 0) {
      ref.read(editorProvider.notifier).addTimeToLog(minutes);
    }
    return minutes;
  }

  /// Toggle between running and stopped.
  void toggle() => state.isRunning ? stop() : start();
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final stitchingTimerProvider =
    NotifierProvider<StitchingTimerNotifier, StitchingTimerState>(
  StitchingTimerNotifier.new,
);
