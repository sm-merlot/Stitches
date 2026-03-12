import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;
  final Color aidaColor;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.aidaColor = Colors.white,
  });

  AppSettings copyWith({bool? useDmc, bool? keepScreenOn, Color? aidaColor}) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      aidaColor: aidaColor ?? this.aidaColor,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyAidaColor = 'aida_color';

  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final aidaValue = prefs.getInt(_keyAidaColor);
    state = AppSettings(
      useDmc: prefs.getBool(_keyUseDmc) ?? true,
      keepScreenOn: prefs.getBool(_keyKeepScreenOn) ?? false,
      aidaColor: aidaValue != null ? Color(aidaValue) : Colors.white,
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

  Future<void> setAidaColor(Color value) async {
    state = state.copyWith(aidaColor: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAidaColor, value.toARGB32());
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
