import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/progress/progress_log.dart';
import '../services/file_service.dart';
import 'editor/editor_provider.dart';
import 'settings_provider.dart';
import 'workspace_provider.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

/// SharedPreferences key for the per-workspace session map (v2 multi-timer).
const _kSessionsKey = 'stitching_timer_sessions_v2';

/// Map key used when no workspace is open (standalone file).
const _kStandaloneKey = '_standalone';

/// Exposed for tests that need to inject session state directly.
@visibleForTesting
const kTimerStandaloneKey = _kStandaloneKey;

String _wsKey(String? workspaceId) => workspaceId ?? _kStandaloneKey;

// ─── Per-session state ────────────────────────────────────────────────────────

class TimerSession {
  final bool isRunning;
  final DateTime? sessionStart;
  final int tickCount;
  final bool showInactivityPrompt;
  final String? filePath;
  final String? patternName;

  const TimerSession({
    this.isRunning = false,
    this.sessionStart,
    this.tickCount = 0,
    this.showInactivityPrompt = false,
    this.filePath,
    this.patternName,
  });

  Duration get elapsed =>
      isRunning && sessionStart != null
          ? DateTime.now().difference(sessionStart!)
          : Duration.zero;

  TimerSession copyWith({
    bool? isRunning,
    DateTime? sessionStart,
    bool clearSessionStart = false,
    int? tickCount,
    bool? showInactivityPrompt,
    String? filePath,
    bool clearFilePath = false,
    String? patternName,
    bool clearPatternName = false,
  }) =>
      TimerSession(
        isRunning: isRunning ?? this.isRunning,
        sessionStart:
            clearSessionStart ? null : (sessionStart ?? this.sessionStart),
        tickCount: tickCount ?? this.tickCount,
        showInactivityPrompt:
            showInactivityPrompt ?? this.showInactivityPrompt,
        filePath: clearFilePath ? null : (filePath ?? this.filePath),
        patternName:
            clearPatternName ? null : (patternName ?? this.patternName),
      );
}

// ─── Top-level state ──────────────────────────────────────────────────────────

class StitchingTimerState {
  /// Active sessions keyed by workspace ID (or [_kStandaloneKey] for null).
  final Map<String, TimerSession> sessions;

  const StitchingTimerState({this.sessions = const {}});

  /// Session for [workspaceId], or null if none exists.
  TimerSession? sessionFor(String? workspaceId) =>
      sessions[_wsKey(workspaceId)];

  bool get anyRunning => sessions.values.any((s) => s.isRunning);

  StitchingTimerState _withSession(String? workspaceId, TimerSession session) =>
      StitchingTimerState(
        sessions: {...sessions, _wsKey(workspaceId): session},
      );

  StitchingTimerState _withoutSession(String? workspaceId) {
    final updated = Map<String, TimerSession>.from(sessions);
    updated.remove(_wsKey(workspaceId));
    return StitchingTimerState(sessions: updated);
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class StitchingTimerNotifier extends Notifier<StitchingTimerState> {
  // Per-workspace infrastructure — keyed by _wsKey(workspaceId).
  final Map<String, Timer> _tickers = {};
  final Map<String, Timer> _inactivityCheckers = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, Stopwatch> _stopwatches = {};
  final Map<String, DateTime?> _lastInteractionAt = {};
  final Map<String, DateTime?> _lastPersistedAt = {};

  /// Per-workspace start-prompt snooze. Separate from session state so it
  /// survives stop() without creating a ghost session entry.
  final Map<String, DateTime> _snoozeUntil = {};

  static const _debounceDelay = Duration(seconds: 10);
  static const _maxWait = Duration(minutes: 1);

  /// Last interaction for a specific workspace (used by the timer chip sheet).
  DateTime? lastInteractionForWorkspace(String? workspaceId) =>
      _lastInteractionAt[_wsKey(workspaceId)];

  /// Convenience: last interaction for the current workspace.
  DateTime? get lastInteractionAt {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    return _lastInteractionAt[_wsKey(workspaceId)];
  }

  @visibleForTesting
  DateTime now() => DateTime.now();

  @override
  StitchingTimerState build() {
    ref.onDispose(() {
      for (final t in _tickers.values) { t.cancel(); }
      for (final t in _inactivityCheckers.values) { t.cancel(); }
      for (final t in _debounceTimers.values) { t.cancel(); }
      for (final sw in _stopwatches.values) { sw.stop(); }
    });

    _restorePersistedSessions();
    return const StitchingTimerState();
  }

Future<void> _restorePersistedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kSessionsKey);
    if (json == null) return;

    final Map<String, dynamic> map;
    try {
      map = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final now = this.now();
    var nextState = const StitchingTimerState();

    for (final entry in map.entries) {
      final key = entry.key;
      final data = entry.value as Map<String, dynamic>?;
      if (data == null) continue;

      final workspaceId = data['workspaceId'] as String?;

      // Restore snooze (may exist even without a running session).
      final pauseMs = data['pauseReminderUntilMs'] as int?;
      if (pauseMs != null) {
        final until = DateTime.fromMillisecondsSinceEpoch(pauseMs);
        if (now.isBefore(until)) _snoozeUntil[key] = until;
      }

      final startMs = data['sessionStartMs'] as int?;
      if (startMs == null) continue; // snooze-only entry — nothing else to restore

      final sessionStart = DateTime.fromMillisecondsSinceEpoch(startMs);
      if (now.difference(sessionStart).inHours > 24) continue; // stale

      final filePath = data['filePath'] as String?;
      if (filePath != null && !File(filePath).existsSync()) continue;

      final lastMs = data['lastInteractionMs'] as int?;
      final lastInteraction = lastMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastMs)
          : sessionStart;
      _lastInteractionAt[key] = lastInteraction;
      _lastPersistedAt[key] = lastInteraction;

      final session = TimerSession(
        isRunning: true,
        sessionStart: sessionStart,
        tickCount: 0,
        filePath: filePath,
        patternName: data['patternName'] as String?,
      );
      nextState = nextState._withSession(workspaceId, session);
      _startTimersForWorkspace(key, workspaceId);
    }

    if (nextState.sessions.isNotEmpty) {
      state = nextState;
    }
  }

  /// Serialises all running sessions (plus active snoozes) to SharedPreferences.
  Future<void> _persistAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final now = this.now();
    final map = <String, dynamic>{};

    // Collect all keys that have either a running session or an active snooze.
    final allKeys = {
      ...state.sessions.keys,
      ..._snoozeUntil.keys,
    };

    for (final key in allKeys) {
      final session = state.sessions[key];
      final snooze = _snoozeUntil[key];
      final hasActiveSnooze = snooze != null && now.isBefore(snooze);

      if (session?.isRunning != true && !hasActiveSnooze) continue;

      final workspaceId = key == _kStandaloneKey ? null : key;
      map[key] = {
        if (session?.isRunning == true && session?.sessionStart != null)
          'sessionStartMs': session!.sessionStart!.millisecondsSinceEpoch,
        if (session?.isRunning == true)
          'lastInteractionMs': _lastInteractionAt[key]?.millisecondsSinceEpoch,
        if (session?.filePath != null) 'filePath': session!.filePath,
        if (session?.patternName != null) 'patternName': session!.patternName,
        'workspaceId': workspaceId,
        if (hasActiveSnooze) 'pauseReminderUntilMs': snooze.millisecondsSinceEpoch,
      };
    }

    if (map.isEmpty) {
      await prefs.remove(_kSessionsKey);
    } else {
      await prefs.setString(_kSessionsKey, jsonEncode(map));
    }
  }

  void _startTimersForWorkspace(String key, String? workspaceId) {
    _tickers[key]?.cancel();
    _tickers[key] = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = state.sessions[key];
      if (session == null) return;
      state = state._withSession(
          workspaceId, session.copyWith(tickCount: session.tickCount + 1));
    });
    _inactivityCheckers[key]?.cancel();
    _inactivityCheckers[key] =
        Timer.periodic(const Duration(seconds: 5), (_) { // TEST
      _checkInactivityForWorkspace(key, workspaceId);
    });
  }

  // ── Start / stop ───────────────────────────────────────────────────────────

  void start() async {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);

    if (state.sessions[key]?.isRunning == true) return;

    final now = this.now();
    final editorState = ref.read(editorProvider);
    final filePath = editorState.filePath;
    final patternName = editorState.pattern.name;

    _lastInteractionAt[key] = now;
    _lastPersistedAt[key] = now;
    (_stopwatches[key] ??= Stopwatch())
      ..reset()
      ..start();

    state = state._withSession(
      workspaceId,
      TimerSession(
        isRunning: true,
        sessionStart: now,
        showInactivityPrompt: false,
        filePath: filePath,
        patternName: patternName.isNotEmpty ? patternName : null,
      ),
    );

    _startTimersForWorkspace(key, workspaceId);
    await _persistAllSessions();
  }

  /// Stops the timer for [workspaceId] (defaults to current workspace).
  int stop({DateTime? stopAt, String? workspaceId}) {
    final effectiveWorkspaceId =
        workspaceId ?? ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(effectiveWorkspaceId);

    final session = state.sessions[key];
    if (session == null || !session.isRunning) return 0;

    _tickers[key]?.cancel();
    _tickers.remove(key);
    _inactivityCheckers[key]?.cancel();
    _inactivityCheckers.remove(key);
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);

    final sessionStart = session.sessionStart!;
    final timerFilePath = session.filePath;

    int totalMinutes;
    DateTime effectiveStop;

    if (stopAt != null) {
      effectiveStop = stopAt;
      totalMinutes = stopAt.difference(sessionStart).inMinutes;
    } else {
      final sw = _stopwatches[key];
      if (sw != null && sw.elapsed > Duration.zero) {
        effectiveStop = now();
        totalMinutes = sw.elapsed.inMinutes;
      } else {
        effectiveStop = now();
        totalMinutes = effectiveStop.difference(sessionStart).inMinutes;
      }
    }

    _stopwatches[key]?.stop();
    _stopwatches[key]?.reset();
    _lastInteractionAt.remove(key);
    _lastPersistedAt.remove(key);

    state = state._withoutSession(effectiveWorkspaceId);
    unawaited(_persistAllSessions());

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

  void toggle() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    if (state.sessions[_wsKey(workspaceId)]?.isRunning == true) {
      stop();
    } else {
      start();
    }
  }

  // ── Interaction tracking ───────────────────────────────────────────────────

  void recordInteraction() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    final session = state.sessions[key];
    if (session == null || !session.isRunning) return;
    if (session.filePath != null) {
      final currentFile = ref.read(editorProvider).filePath;
      if (currentFile != session.filePath) return;
    }
    _lastInteractionAt[key] = now();

    final lastPersisted = _lastPersistedAt[key];
    if (lastPersisted == null || now().difference(lastPersisted) >= _maxWait) {
      _persistInteractionForWorkspace(key);
      return;
    }
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] =
        Timer(_debounceDelay, () => _persistInteractionForWorkspace(key));
  }

  void _persistInteractionForWorkspace(String key) {
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);
    _lastPersistedAt[key] = _lastInteractionAt[key];
    unawaited(_persistAllSessions());
  }

  // ── Inactivity prompt ──────────────────────────────────────────────────────

  void _checkInactivityForWorkspace(String key, String? workspaceId) {
    final session = state.sessions[key];
    if (session == null || !session.isRunning || session.showInactivityPrompt) {
      return;
    }
    // Only prompt when the user is currently in this workspace.
    final currentWorkspaceId = ref.read(workspaceProvider).workspace?.id;
    if (currentWorkspaceId != workspaceId) return;

    final editorState = ref.read(editorProvider);
    if (!editorState.stitchMode) return;
    if (session.filePath != null && editorState.filePath != session.filePath) {
      return;
    }
    final settings = ref.read(settingsProvider);
    if (!settings.inactivityCheckEnabled) return;
    const threshold = Duration(seconds: 10); // TEST
    final last = _lastInteractionAt[key] ?? session.sessionStart;
    if (last == null) return;
    if (now().difference(last) >= threshold) {
      state = state._withSession(
          workspaceId, session.copyWith(showInactivityPrompt: true));
    }
  }

  void checkInactivityNow() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    _checkInactivityForWorkspace(key, workspaceId);
  }

  void acknowledgeInactivityPrompt() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    final session = state.sessions[key];
    if (session == null) return;
    state = state._withSession(
        workspaceId, session.copyWith(showInactivityPrompt: false));
  }

  // ── Start / swap prompt ────────────────────────────────────────────────────

  /// Whether to show "start a timer?" for the current workspace.
  bool shouldShowStartPrompt() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    if (state.sessions[key]?.isRunning == true) return false;
    final settings = ref.read(settingsProvider);
    if (settings.disableTimerStartPrompt) return false;
    final snooze = _snoozeUntil[key];
    if (snooze != null && now().isBefore(snooze)) return false;
    return true;
  }

  /// Whether to show "swap timer?" — only when the SAME workspace's timer is
  /// running for a different pattern than the one currently open.
  bool shouldShowSwapPrompt() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final session = state.sessionFor(workspaceId);
    if (session?.isRunning != true) return false;
    final settings = ref.read(settingsProvider);
    if (settings.disableTimerStartPrompt) return false;
    final timerFilePath = session!.filePath;
    if (timerFilePath == null) return false;
    return ref.read(editorProvider).filePath != timerFilePath;
  }

  void swapTimer() {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    final session = state.sessions[key];
    if (session?.isRunning != true) return;

    final sessionStart = session!.sessionStart!;
    final oldFilePath = session.filePath;
    final effectiveStop = now();
    final sw = _stopwatches[key];
    final totalMinutes = sw != null && sw.elapsed > Duration.zero
        ? sw.elapsed.inMinutes
        : effectiveStop.difference(sessionStart).inMinutes;

    stop(); // _logTime skips — paths differ; we log manually below
    start();

    if (oldFilePath != null && totalMinutes > 0) {
      unawaited(
        _logTimeToFile(oldFilePath, sessionStart, effectiveStop, totalMinutes),
      );
    }
  }

  Future<void> _logTimeToFile(
    String filePath,
    DateTime sessionStart,
    DateTime effectiveStop,
    int totalMinutes,
  ) async {
    try {
      final (pattern, _, wasCompressed) =
          await FileService.openFileFromPath(filePath);

      final startDate =
          DateTime(sessionStart.year, sessionStart.month, sessionStart.day);
      final stopDate =
          DateTime(effectiveStop.year, effectiveStop.month, effectiveStop.day);

      var log = pattern.progressLog;
      if (startDate == stopDate) {
        log = _appendMinutes(log, totalMinutes, _isoDate(effectiveStop));
      } else {
        final midnight = stopDate;
        final prevMins = midnight.difference(sessionStart).inMinutes;
        final stopMins = effectiveStop.difference(midnight).inMinutes;
        if (prevMins > 0) log = _appendMinutes(log, prevMins, _isoDate(sessionStart));
        if (stopMins > 0) log = _appendMinutes(log, stopMins, _isoDate(effectiveStop));
      }

      final updated = pattern.copyWith(progressLog: log);
      await FileService.saveFile(updated, filePath, compress: wasCompressed);
    } catch (e) {
      debugPrint('[Timer] swapTimer: could not log time to $filePath: $e');
    }
  }

  static List<ProgressLogEntry> _appendMinutes(
    List<ProgressLogEntry> log,
    int minutes,
    String isoDate,
  ) {
    final existing = log.where((e) => e.isoDate == isoDate).firstOrNull;
    final updated = existing != null
        ? existing.copyWith(minutesSpent: existing.minutesSpent + minutes)
        : ProgressLogEntry(
            isoDate: isoDate,
            stitchCount: 0,
            backstitchCount: 0,
            minutesSpent: minutes,
          );
    return [...log.where((e) => e.isoDate != isoDate), updated];
  }

  Future<void> snoozeStartPrompt() async {
    final workspaceId = ref.read(workspaceProvider).workspace?.id;
    final key = _wsKey(workspaceId);
    _snoozeUntil[key] = now().add(const Duration(minutes: 10));
    await _persistAllSessions();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final stitchingTimerProvider =
    NotifierProvider<StitchingTimerNotifier, StitchingTimerState>(
  StitchingTimerNotifier.new,
);
