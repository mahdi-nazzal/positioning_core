import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF1F3A5F),
      brightness: Brightness.light,
    );
    return base.copyWith(
      cardTheme: const CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF1F3A5F),
      brightness: Brightness.dark,
    );
    return base.copyWith(
      cardTheme: const CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
