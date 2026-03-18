import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;
  final bool autoSaveLocal;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.autoSaveLocal = false,
  });

  AppSettings copyWith({bool? useDmc, bool? keepScreenOn, bool? autoSaveLocal}) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      autoSaveLocal: autoSaveLocal ?? this.autoSaveLocal,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyAutoSaveLocal = 'auto_save_local';

  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      useDmc: prefs.getBool(_keyUseDmc) ?? true,
      keepScreenOn: prefs.getBool(_keyKeepScreenOn) ?? false,
      autoSaveLocal: prefs.getBool(_keyAutoSaveLocal) ?? false,
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

  Future<void> setAutoSaveLocal(bool value) async {
    state = state.copyWith(autoSaveLocal: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSaveLocal, value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
