// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Palette ──────────────────────────────────────────────────────────────────
// Deep navy base with violet accent and four vivid token colours.
// The "signature" element: every player colour has a matching gradient
// used for glows, active states, and the win screen.
class AppColors {
  // Surface
  static const bg         = Color(0xFF0D0D1A);
  static const surface    = Color(0xFF16162B);
  static const card       = Color(0xFF1E1E38);
  static const border     = Color(0xFF2E2E52);

  // Accent
  static const violet     = Color(0xFF7C3AED);
  static const violetLit  = Color(0xFF9F67FF);
  static const gold       = Color(0xFFFFB800);

  // Player tokens
  static const red        = Color(0xFFE53935);
  static const green      = Color(0xFF43A047);
  static const yellow     = Color(0xFFFDD835);
  static const blue       = Color(0xFF1E88E5);

  static const List<Color> players = [red, green, yellow, blue];

  // Glows (used in BoxShadow)
  static const List<Color> glows = [
    Color(0x66E53935),
    Color(0x6643A047),
    Color(0x66FDD835),
    Color(0x661E88E5),
  ];

  // Board cell colours
  static const boardTrack   = Color(0xFF252545);
  static const boardSafe    = Color(0xFF37474F);
  static const boardHome    = Color(0xFF4A148C);
  static const boardNestRed    = Color(0xFFC62828);
  static const boardNestGreen  = Color(0xFF2E7D32);
  static const boardNestYellow = Color(0xFFF9A825);
  static const boardNestBlue   = Color(0xFF1565C0);

  static const List<Color> nests = [
    boardNestRed, boardNestGreen, boardNestYellow, boardNestBlue,
  ];

  static const List<Color> housePaths = [
    Color(0x99EF9A9A),
    Color(0x99A5D6A7),
    Color(0x99FFF59D),
    Color(0x9990CAF9),
  ];
}

// ── Text styles ───────────────────────────────────────────────────────────────
class AppText {
  // Rajdhani for display (bold, slightly condensed — suits a board game)
  // Inter for body (clean, readable at small sizes on mobile)
  static TextTheme get theme => TextTheme(
    displayLarge:  GoogleFonts.rajdhani(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
    displayMedium: GoogleFonts.rajdhani(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
    displaySmall:  GoogleFonts.rajdhani(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
    headlineMedium:GoogleFonts.rajdhani(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
    titleLarge:    GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
    titleMedium:   GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
    bodyLarge:     GoogleFonts.inter(fontSize: 14, color: Colors.white70),
    bodyMedium:    GoogleFonts.inter(fontSize: 12, color: Colors.white60),
    labelLarge:    GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    labelSmall:    GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white54),
  );
}

// ── Theme ─────────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.violet,
      secondary: AppColors.gold,
      surface:   AppColors.surface,
      error:     Color(0xFFCF6679),
    ),
    textTheme: AppText.theme,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.violet,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.violet, width: 2),
      ),
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle:  const TextStyle(color: Colors.white30),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.card,
      contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
