import 'package:flutter/material.dart';

/// Tema visual de la app (Material 3), en tonos de cuidado / salud.
class AppTheme {
  static const _seed = Color(0xFF00897B); // teal

  // Modo claro estilo "Sense Care": fondo crema cálido y tarjetas blancas.
  static const _cream = Color(0xFFF6EBDC);
  static const _card = Color(0xFFFFFFFF);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final background = isLight ? _cream : scheme.surface;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardTheme: isLight
          ? CardThemeData(
              color: _card,
              surfaceTintColor: _card,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFEADDC9)),
              ),
            )
          : null,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
