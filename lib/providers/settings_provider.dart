import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How to sort colours in the sidebar thread list.
enum ColourSortMode {
  byId,          // DMC or Anchor numeric code (default)
  byStitchCount, // most stitches first
}

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;

  /// Apple Pencil paste mode: when true, pencil positions the ghost and a
  /// finger tap confirms placement (instead of pencil tap stamping immediately).
  final bool pencilPasteConfirm;

  /// Whether new patterns are saved as gzip-compressed .stitches files.
  /// Existing files keep their compression state when re-saved.
  final bool compressNewFiles;

  /// Colour list sort mode.
  final ColourSortMode colourSortMode;

  /// When true, fully-completed colours sink to the bottom of the list.
  final bool completedColoursLast;

  /// When true, suppress the "start a timer?" prompt after marking done.
  final bool disableTimerStartPrompt;

  /// When true, show an inactivity prompt when the timer runs without any
  /// stitch-mode activity for [inactivityThresholdMinutes] minutes.
  final bool inactivityCheckEnabled;

  /// Minutes of stitch-mode inactivity before the "are you still stitching?"
  /// prompt is shown. Only used when [inactivityCheckEnabled] is true.
  final int inactivityThresholdMinutes;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.pencilPasteConfirm = false,
    this.compressNewFiles = true,
    this.colourSortMode = ColourSortMode.byId,
    this.completedColoursLast = false,
    this.disableTimerStartPrompt = false,
    this.inactivityCheckEnabled = true,
    this.inactivityThresholdMinutes = 15,
  });

  AppSettings copyWith({
    bool? useDmc,
    bool? keepScreenOn,
    bool? pencilPasteConfirm,
    bool? compressNewFiles,
    ColourSortMode? colourSortMode,
    bool? completedColoursLast,
    bool? disableTimerStartPrompt,
    bool? inactivityCheckEnabled,
    int? inactivityThresholdMinutes,
  }) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      pencilPasteConfirm: pencilPasteConfirm ?? this.pencilPasteConfirm,
      compressNewFiles: compressNewFiles ?? this.compressNewFiles,
      colourSortMode: colourSortMode ?? this.colourSortMode,
      completedColoursLast: completedColoursLast ?? this.completedColoursLast,
      disableTimerStartPrompt: disableTimerStartPrompt ?? this.disableTimerStartPrompt,
      inactivityCheckEnabled: inactivityCheckEnabled ?? this.inactivityCheckEnabled,
      inactivityThresholdMinutes: inactivityThresholdMinutes ?? this.inactivityThresholdMinutes,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyPencilPasteConfirm = 'pencil_paste_confirm';
  static const _keyCompressNewFiles = 'compress_new_files';
  static const _keyColourSortMode = 'colour_sort_mode';
  static const _keyCompletedColoursLast = 'completed_colours_last';
  static const _keyDisableTimerStartPrompt = 'disable_timer_start_prompt';
  static const _keyInactivityCheckEnabled = 'inactivity_check_enabled';
  static const _keyInactivityThresholdMinutes = 'inactivity_threshold_minutes';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final sortIdx = prefs.getInt(_keyColourSortMode) ?? 0;
    state = AppSettings(
      useDmc: prefs.getBool(_keyUseDmc) ?? true,
      keepScreenOn: prefs.getBool(_keyKeepScreenOn) ?? false,
      pencilPasteConfirm: prefs.getBool(_keyPencilPasteConfirm) ?? false,
      compressNewFiles: prefs.getBool(_keyCompressNewFiles) ?? true,
      colourSortMode: sortIdx < ColourSortMode.values.length
          ? ColourSortMode.values[sortIdx]
          : ColourSortMode.byId,
      completedColoursLast: prefs.getBool(_keyCompletedColoursLast) ?? false,
      disableTimerStartPrompt: prefs.getBool(_keyDisableTimerStartPrompt) ?? false,
      inactivityCheckEnabled: prefs.getBool(_keyInactivityCheckEnabled) ?? true,
      inactivityThresholdMinutes: prefs.getInt(_keyInactivityThresholdMinutes) ?? 15,
    );
  }

  Future<void> setUseDmc(bool value) async {
    state = state.copyWith(useDmc: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseDmc, value);
  }

  Future<void> setKeepScreenOn(bool value) async {
    state = state.copyWith(keepScreenOn: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepScreenOn, value);
  }

  Future<void> setPencilPasteConfirm(bool value) async {
    state = state.copyWith(pencilPasteConfirm: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPencilPasteConfirm, value);
  }

  Future<void> setCompressNewFiles(bool value) async {
    state = state.copyWith(compressNewFiles: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompressNewFiles, value);
  }

  Future<void> setColourSortMode(ColourSortMode value) async {
    state = state.copyWith(colourSortMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyColourSortMode, value.index);
  }

  Future<void> setCompletedColoursLast(bool value) async {
    state = state.copyWith(completedColoursLast: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompletedColoursLast, value);
  }

  Future<void> setDisableTimerStartPrompt(bool value) async {
    state = state.copyWith(disableTimerStartPrompt: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDisableTimerStartPrompt, value);
  }

  Future<void> setInactivityCheckEnabled(bool value) async {
    state = state.copyWith(inactivityCheckEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInactivityCheckEnabled, value);
  }

  Future<void> setInactivityThresholdMinutes(int value) async {
    state = state.copyWith(inactivityThresholdMinutes: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInactivityThresholdMinutes, value);
  }

}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
