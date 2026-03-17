import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';

class StitchXApp extends ConsumerWidget {
  const StitchXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.keepScreenOn != next.keepScreenOn) {
        WakelockPlus.toggle(enable: next.keepScreenOn);
      }
    });

    // Apply on first build in case the setting is already true.
    final keepScreenOn = ref.read(settingsProvider).keepScreenOn;
    if (keepScreenOn) WakelockPlus.enable();

    return MaterialApp(
      title: 'StitchX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          scrolledUnderElevation: 1,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
