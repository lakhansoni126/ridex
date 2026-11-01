import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Premium Automotive Palette
  static const Color background = Color(0xFF0F0F11);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color accent = Color(0xFFE53935); // Bold Red
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);

  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        background: background,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 64, fontWeight: FontWeight.bold, color: textPrimary),
        displayMedium: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 18, color: textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 16, color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          elevation: 0,
        ),
      ),
    );
  }
}
