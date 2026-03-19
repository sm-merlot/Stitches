import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
  });

  AppSettings copyWith({bool? useDmc, bool? keepScreenOn}) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';

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
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
