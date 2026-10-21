import 'package:flutter/material.dart';

/// Design tokens ported from the Expo app's `src/theme.ts` (light scheme) with a
/// customizable accent color.
class AppColors {
  static const surface = Color(0xFFFDFCF9);
  static const onSurface = Color(0xFF1C1C1E);
  static const surfaceSecondary = Color(0xFFFFFFFF);
  static const surfaceTertiary = Color(0xFFF2F1EC);
  static const onSurfaceTertiary = Color(0xFF4A4A4C);

  static const brand = Color(0xFF1C1C1E);
  static const onBrand = Color(0xFFFFFFFF);

  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF57F17);
  static const error = Color(0xFFC62828);
  static const info = Color(0xFF00695C);

  static const border = Color(0xFFE5E5EA);
  static const borderStrong = Color(0xFFC7C7CC);
  static const muted = Color(0xFF6E6E73);

  /// Default book/post-it color used by the backend.
  static const defaultBook = Color(0xFF8D6E63);
}

/// Returns black or white depending on the luminance of [hex] (#RRGGBB).
Color contrastOn(Color c) {
  final lum = (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;
  return lum > 0.6 ? const Color(0xFF1C1C1E) : Colors.white;
}

/// Parses a `#RRGGBB` string into a [Color], falling back to the default book color.
Color colorFromHex(String? hex) {
  final h = (hex ?? '').replaceAll('#', '').trim();
  if (h.length != 6) return AppColors.defaultBook;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return AppColors.defaultBook;
  return Color(0xFF000000 | v);
}

/// Dark-scheme tokens (from `src/theme.ts` dark palette).
class AppDarkColors {
  static const surface = Color(0xFF121212);
  static const onSurface = Color(0xFFF5F5F7);
  static const surfaceSecondary = Color(0xFF1E1E1E);
  static const surfaceTertiary = Color(0xFF2C2C2E);
  static const border = Color(0xFF38383A);
}

/// Builds the light or dark theme. [accent] null = default (black / white).
ThemeData buildTheme(Color? accentOrNull, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? AppDarkColors.surface : AppColors.surface;
  final onSurface = dark ? AppDarkColors.onSurface : AppColors.onSurface;
  final card = dark ? AppDarkColors.surfaceSecondary : AppColors.surfaceSecondary;
  final border = dark ? AppDarkColors.border : AppColors.border;
  final accent = accentOrNull ?? (dark ? AppDarkColors.onSurface : AppColors.brand);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    onPrimary: contrastOn(accent),
    surface: surface,
    onSurface: onSurface,
    error: AppColors.error,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: contrastOn(accent),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
