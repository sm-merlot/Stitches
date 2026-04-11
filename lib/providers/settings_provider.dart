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

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.pencilPasteConfirm = false,
    this.compressNewFiles = true,
    this.colourSortMode = ColourSortMode.byId,
    this.completedColoursLast = false,
  });

  AppSettings copyWith({
    bool? useDmc,
    bool? keepScreenOn,
    bool? pencilPasteConfirm,
    bool? compressNewFiles,
    ColourSortMode? colourSortMode,
    bool? completedColoursLast,
  }) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      pencilPasteConfirm: pencilPasteConfirm ?? this.pencilPasteConfirm,
      compressNewFiles: compressNewFiles ?? this.compressNewFiles,
      colourSortMode: colourSortMode ?? this.colourSortMode,
      completedColoursLast: completedColoursLast ?? this.completedColoursLast,
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
      completedColoursLast:
          prefs.getBool(_keyCompletedColoursLast) ?? false,
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

}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
