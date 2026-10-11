import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

/// Root widget: wires the dark-first theme pair into a plain [MaterialApp].
/// Navigation stays on `Navigator` with custom transitions (no router package).
class ReceiptsApp extends StatelessWidget {
  const ReceiptsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipts',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // dark-first identity
      home: const SplashScreen(),
    );
  }
}
