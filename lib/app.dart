import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class StitchXApp extends StatelessWidget {
  const StitchXApp({super.key});

  @override
  Widget build(BuildContext context) {
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
