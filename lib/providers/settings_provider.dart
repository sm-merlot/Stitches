import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;

  /// Apple Pencil paste mode: when true, pencil positions the ghost and a
  /// finger tap confirms placement (instead of pencil tap stamping immediately).
  final bool pencilPasteConfirm;

  /// Whether new patterns are saved as gzip-compressed .stitches files.
  /// Existing files keep their compression state when re-saved.
  final bool compressNewFiles;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.pencilPasteConfirm = false,
    this.compressNewFiles = true,
  });

  AppSettings copyWith({
    bool? useDmc,
    bool? keepScreenOn,
    bool? pencilPasteConfirm,
    bool? compressNewFiles,
  }) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      pencilPasteConfirm: pencilPasteConfirm ?? this.pencilPasteConfirm,
      compressNewFiles: compressNewFiles ?? this.compressNewFiles,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyPencilPasteConfirm = 'pencil_paste_confirm';
  static const _keyCompressNewFiles = 'compress_new_files';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = AppSettings(
      useDmc: prefs.getBool(_keyUseDmc) ?? true,
      keepScreenOn: prefs.getBool(_keyKeepScreenOn) ?? false,
      pencilPasteConfirm: prefs.getBool(_keyPencilPasteConfirm) ?? false,
      compressNewFiles: prefs.getBool(_keyCompressNewFiles) ?? true,
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

}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
