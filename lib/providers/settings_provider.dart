import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool useDmc;
  final bool keepScreenOn;

  /// Apple Pencil paste mode: when true, pencil positions the ghost and a
  /// finger tap confirms placement (instead of pencil tap stamping immediately).
  final bool pencilPasteConfirm;

  const AppSettings({
    this.useDmc = true,
    this.keepScreenOn = false,
    this.pencilPasteConfirm = false,
  });

  AppSettings copyWith({
    bool? useDmc,
    bool? keepScreenOn,
    bool? pencilPasteConfirm,
  }) {
    return AppSettings(
      useDmc: useDmc ?? this.useDmc,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      pencilPasteConfirm: pencilPasteConfirm ?? this.pencilPasteConfirm,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyUseDmc = 'use_dmc';
  static const _keyKeepScreenOn = 'keep_screen_on';
  static const _keyPencilPasteConfirm = 'pencil_paste_confirm';

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

}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
