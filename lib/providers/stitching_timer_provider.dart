import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'editor/editor_provider.dart';
import 'settings_provider.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kSessionStartKey       = 'stitching_timer_session_start_ms';
const _kSessionFileKey        = 'stitching_timer_session_file';
const _kSessionPatternNameKey = 'stitching_timer_session_pattern_name';
const _kLastInteractionKey    = 'stitching_timer_last_interaction_ms';
const _kPauseReminderUntilKey = 'stitching_timer_pause_reminder_until_ms';

// ─── State ────────────────────────────────────────────────────────────────────

class StitchingTimerState {
  /// Whether a session is currently running.
  final bool isRunning;

  /// When the current session started (null when not running).
  final DateTime? sessionStart;

  /// Increments every second while running — drives widget rebuilds.
  final int tickCount;

  /// When true, EditorScreen / WorkspaceScreen should show the inactivity dialog.
  final bool showInactivityPrompt;

  /// When non-null, the start-timer prompt is snoozed until this time.
  final DateTime? pauseReminderUntil;

  /// File path of the pattern this timer session belongs to.
  /// Null when timer is not running.
  final String? timerFilePath;

  /// Human-readable name of the pattern (from [CrossStitchPattern.name]).
  /// Null when timer is not running.
  final String? timerPatternName;

  const StitchingTimerState({
    this.isRunning = false,
    this.sessionStart,
    this.tickCount = 0,
    this.showInactivityPrompt = false,
    this.pauseReminderUntil,
    this.timerFilePath,
    this.timerPatternName,
  });

  /// Elapsed duration of the current session (wall-clock, for display only).
  Duration get elapsed =>
      isRunning && sessionStart != null
          ? DateTime.now().difference(sessionStart!)
          : Duration.zero;

  StitchingTimerState copyWith({
    bool? isRunning,
    DateTime? sessionStart,
    bool clearSessionStart = false,
    int? tickCount,
    bool? showInactivityPrompt,
    DateTime? pauseReminderUntil,
    bool clearPauseReminderUntil = false,
    String? timerFilePath,
    bool clearTimerFilePath = false,
    String? timerPatternName,
    bool clearTimerPatternName = false,
  }) =>
      StitchingTimerState(
        isRunning: isRunning ?? this.isRunning,
        sessionStart:
            clearSessionStart ? null : (sessionStart ?? this.sessionStart),
        tickCount: tickCount ?? this.tickCount,
        showInactivityPrompt:
            showInactivityPrompt ?? this.showInactivityPrompt,
        pauseReminderUntil: clearPauseReminderUntil
            ? null
            : (pauseReminderUntil ?? this.pauseReminderUntil),
        timerFilePath:
            clearTimerFilePath ? null : (timerFilePath ?? this.timerFilePath),
        timerPatternName: clearTimerPatternName
            ? null
            : (timerPatternName ?? this.timerPatternName),
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class StitchingTimerNotifier extends Notifier<StitchingTimerState> {
  Timer? _ticker;
  Timer? _inactivityChecker;
  Timer? _debounceTimer;

  /// Monotonic clock for elapsed calculation — immune to DST and wall-clock
  /// adjustments. Only valid for the current active session; not restored
  /// after an app kill (falls back to wall-clock diff in that case).
  final Stopwatch _stopwatch = Stopwatch();

  /// Last interaction time. Stored as a private field (not in Riverpod state)
  /// to avoid triggering widget rebuilds on every touch event.
  DateTime? _lastInteractionAt;

  /// Timestamp of the most recent SharedPreferences write for interaction.
  DateTime? _lastPersistedAt;

  static const _debounceDelay = Duration(seconds: 10);
  static const _maxWait = Duration(minutes: 1);

  /// Exposes last interaction time for callers (e.g. stop(stopAt:)).
  DateTime? get lastInteractionAt => _lastInteractionAt;

  /// Returns the current wall-clock time. Override in tests to control time.
  @visibleForTesting
  DateTime now() => DateTime.now();

  @override
  StitchingTimerState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _inactivityChecker?.cancel();
      _debounceTimer?.cancel();
      _stopwatch.stop();
    });
    _restorePersistedSession();
    return const StitchingTimerState();
  }

  Future<void> _restorePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kSessionStartKey);
    if (ms == null) return;

    // Stale session (> 24 h) — discard.
    final savedStart = DateTime.fromMillisecondsSinceEpoch(ms);
    if (now().difference(savedStart).inHours > 24) {
      await _clearPersistedSession(prefs);
      return;
    }

    // If the file no longer exists, discard the session silently.
    final savedFile = prefs.getString(_kSessionFileKey);
    if (savedFile != null && !File(savedFile).existsSync()) {
      await _clearPersistedSession(prefs);
      return;
    }

    // Restore last interaction (fall back to session start if not persisted).
    final lastMs = prefs.getInt(_kLastInteractionKey);
    _lastInteractionAt = lastMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastMs)
        : savedStart;
    _lastPersistedAt = _lastInteractionAt;

    // Restore snooze state.
    final pauseMs = prefs.getInt(_kPauseReminderUntilKey);
    final pauseUntil = pauseMs != null
        ? DateTime.fromMillisecondsSinceEpoch(pauseMs)
        : null;

    final savedPatternName = prefs.getString(_kSessionPatternNameKey);

    state = StitchingTimerState(
      isRunning: true,
      sessionStart: savedStart,
      tickCount: 0,
      pauseReminderUntil: pauseUntil,
      timerFilePath: savedFile,
      timerPatternName: savedPatternName,
    );

    // Stopwatch is NOT started for restored sessions — stop() detects this
    // and falls back to wall-clock diff (accepting the rare DST risk).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(tickCount: state.tickCount + 1);
    });
    _inactivityChecker = Timer.periodic(const Duration(seconds: 5), (_) { // TEST
      _checkInactivity();
    });
  }

  Future<void> _clearPersistedSession(SharedPreferences prefs) async {
    await prefs.remove(_kSessionStartKey);
    await prefs.remove(_kSessionFileKey);
    await prefs.remove(_kSessionPatternNameKey);
    await prefs.remove(_kLastInteractionKey);
  }

  /// Start the timer. No-op if already running.
  void start() async {
    if (state.isRunning) return;
    final now = this.now();
    final editorState = ref.read(editorProvider);
    final filePath = editorState.filePath;
    final patternName = editorState.pattern.name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSessionStartKey, now.millisecondsSinceEpoch);
    if (filePath != null) {
      await prefs.setString(_kSessionFileKey, filePath);
    }
    if (patternName.isNotEmpty) {
      await prefs.setString(_kSessionPatternNameKey, patternName);
    }

    _lastInteractionAt = now;
    _lastPersistedAt = now;
    _stopwatch
      ..reset()
      ..start();

    state = state.copyWith(
      isRunning: true,
      sessionStart: now,
      showInactivityPrompt: false,
      timerFilePath: filePath,
      timerPatternName: patternName.isNotEmpty ? patternName : null,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(tickCount: state.tickCount + 1);
    });
    _inactivityChecker = Timer.periodic(const Duration(seconds: 5), (_) { // TEST
      _checkInactivity();
    });
  }

  /// Stop the timer and persist elapsed minutes to the progress log.
  ///
  /// [stopAt] backdates the stop time (e.g. to last interaction). When null,
  /// uses the monotonic stopwatch elapsed for active sessions (DST-safe), or
  /// falls back to wall-clock diff for sessions restored after an app kill.
  ///
  /// Returns the total number of whole minutes recorded.
  int stop({DateTime? stopAt}) {
    if (!state.isRunning) return 0;

    _ticker?.cancel();
    _ticker = null;
    _inactivityChecker?.cancel();
    _inactivityChecker = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;

    final sessionStart = state.sessionStart!;
    final timerFilePath = state.timerFilePath; // capture before state cleared
    int totalMinutes;
    DateTime effectiveStop;

    if (stopAt != null) {
      // Backdate: calculate from session start to the given stop time.
      effectiveStop = stopAt;
      totalMinutes = stopAt.difference(sessionStart).inMinutes;
    } else if (_stopwatch.elapsed > Duration.zero) {
      // Active session: use monotonic stopwatch (immune to DST/NTP changes).
      effectiveStop = now();
      totalMinutes = _stopwatch.elapsed.inMinutes;
    } else {
      // Restored session: stopwatch was reset on kill — fall back to wall clock.
      effectiveStop = now();
      totalMinutes = effectiveStop.difference(sessionStart).inMinutes;
    }

    _stopwatch
      ..stop()
      ..reset();
    _lastInteractionAt = null;
    _lastPersistedAt = null;

    state = state.copyWith(
      isRunning: false,
      clearSessionStart: true,
      tickCount: 0,
      showInactivityPrompt: false,
      clearTimerFilePath: true,
      clearTimerPatternName: true,
    );

    SharedPreferences.getInstance().then((p) {
      p.remove(_kSessionStartKey);
      p.remove(_kSessionFileKey);
      p.remove(_kSessionPatternNameKey);
      p.remove(_kLastInteractionKey);
    });

    if (totalMinutes <= 0) return 0;

    _logTime(sessionStart, effectiveStop, totalMinutes,
        timerFilePath: timerFilePath);
    return totalMinutes;
  }

  void _logTime(
    DateTime sessionStart,
    DateTime effectiveStop,
    int totalMinutes, {
    String? timerFilePath,
  }) {
    // If the timer was for a different file than what's currently open, skip
    // logging — better to lose time than log it to the wrong pattern.
    final currentFilePath = ref.read(editorProvider).filePath;
    if (timerFilePath != null && currentFilePath != timerFilePath) return;

    final notifier = ref.read(editorProvider.notifier);
    final startDate =
        DateTime(sessionStart.year, sessionStart.month, sessionStart.day);
    final stopDate =
        DateTime(effectiveStop.year, effectiveStop.month, effectiveStop.day);
    final stopIso = _isoDate(effectiveStop);

    if (startDate == stopDate) {
      notifier.addTimeToLog(totalMinutes, isoDate: stopIso);
    } else {
      // Session crossed midnight — split at the day boundary.
      final midnight = stopDate;
      final minutesPrevDay = midnight.difference(sessionStart).inMinutes;
      final minutesStopDay = effectiveStop.difference(midnight).inMinutes;
      final prevDayIso = _isoDate(sessionStart);
      if (minutesPrevDay > 0) {
        notifier.addTimeToLog(minutesPrevDay, isoDate: prevDayIso);
      }
      if (minutesStopDay > 0) {
        notifier.addTimeToLog(minutesStopDay, isoDate: stopIso);
      }
    }
  }

  static String _isoDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Toggle between running and stopped.
  void toggle() => state.isRunning ? stop() : start();

  // ── Interaction tracking ───────────────────────────────────────────────────

  /// Records that the user interacted with stitch mode right now.
  ///
  /// Updates the in-memory [lastInteractionAt] immediately. Persists to
  /// SharedPreferences using a debounce+maxWait strategy: writes within 10
  /// seconds of activity stopping, or force-writes every 1 minute during
  /// continuous activity. Worst-case OS-kill drift: ~1 minute.
  void recordInteraction() {
    if (!state.isRunning) return;
    // Ignore interactions on a different pattern — don't corrupt the inactivity
    // clock for the pattern that is actually being timed.
    if (state.timerFilePath != null) {
      final currentFile = ref.read(editorProvider).filePath;
      if (currentFile != state.timerFilePath) return;
    }
    _lastInteractionAt = now();

    final lastPersisted = _lastPersistedAt;
    if (lastPersisted == null ||
        now().difference(lastPersisted) >= _maxWait) {
      _persistInteraction();
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _persistInteraction);
  }

  void _persistInteraction() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastPersistedAt = _lastInteractionAt;
    final ts = _lastInteractionAt?.millisecondsSinceEpoch;
    if (ts == null) return;
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kLastInteractionKey, ts));
  }

  // ── Inactivity prompt ──────────────────────────────────────────────────────

  void _checkInactivity() {
    if (!state.isRunning || state.showInactivityPrompt) return;
    // Only check while the user is actively in stitch mode — no false positives
    // when they step away to view a reference image or PDF.
    final editorState = ref.read(editorProvider);
    if (!editorState.stitchMode) return;
    // Don't prompt if the user is stitching a *different* pattern from the one
    // the timer belongs to — they're active, just on another file.
    if (state.timerFilePath != null &&
        editorState.filePath != state.timerFilePath) {
      return;
    }
    final settings = ref.read(settingsProvider);
    if (!settings.inactivityCheckEnabled) return;
    const threshold = Duration(seconds: 10); // TEST
    final last = _lastInteractionAt ?? state.sessionStart;
    if (last == null) return;
    if (now().difference(last) >= threshold) {
      state = state.copyWith(showInactivityPrompt: true);
    }
  }

  /// Immediately checks inactivity without waiting for the next periodic tick.
  /// Called on app resume to handle the "left timer running overnight" scenario.
  void checkInactivityNow() => _checkInactivity();

  /// Clears the inactivity prompt flag. Call immediately before showing the
  /// dialog to prevent a rapid double-fire from triggering two dialogs.
  void acknowledgeInactivityPrompt() {
    state = state.copyWith(showInactivityPrompt: false);
  }

  // ── Start prompt ───────────────────────────────────────────────────────────

  /// Whether the "start a timer?" prompt should be shown right now.
  bool shouldShowStartPrompt() {
    if (state.isRunning) return false;
    final settings = ref.read(settingsProvider);
    if (settings.disableTimerStartPrompt) return false;
    final snoozeUntil = state.pauseReminderUntil;
    if (snoozeUntil != null && now().isBefore(snoozeUntil)) return false;
    return true;
  }

  /// Whether a "swap timer to this pattern?" prompt should be shown.
  ///
  /// True when a timer is running for a *different* pattern than the one
  /// currently open, and the start-prompt setting is not disabled.
  bool shouldShowSwapPrompt() {
    if (!state.isRunning) return false;
    final settings = ref.read(settingsProvider);
    if (settings.disableTimerStartPrompt) return false;
    final timerFilePath = state.timerFilePath;
    if (timerFilePath == null) return false;
    final currentFilePath = ref.read(editorProvider).filePath;
    return currentFilePath != timerFilePath;
  }

  /// Stops the current timer (time for the old pattern is not logged — it
  /// cannot be saved while a different file is open) and starts a fresh
  /// session for the currently open pattern.
  void swapTimer() {
    stop(); // cross-pattern: _logTime skips logging, time is not saved
    start();
  }

  /// Snoozes the start-timer prompt for 10 minutes.
  Future<void> snoozeStartPrompt() async {
    final until = now().add(const Duration(minutes: 10));
    state = state.copyWith(pauseReminderUntil: until);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPauseReminderUntilKey, until.millisecondsSinceEpoch);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final stitchingTimerProvider =
    NotifierProvider<StitchingTimerNotifier, StitchingTimerState>(
  StitchingTimerNotifier.new,
);
