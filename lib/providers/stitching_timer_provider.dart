import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'editor/editor_provider.dart';

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
    return const StitchingTimerState();
  }

  /// Start the timer. No-op if already running.
  void start() {
    if (state.isRunning) return;
    state = state.copyWith(
      isRunning: true,
      sessionStart: DateTime.now(),
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
