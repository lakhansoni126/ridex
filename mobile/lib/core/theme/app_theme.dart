import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Red / black / white glass palette
  static const Color background = Color(0xFF0A0A0B);
  static const Color surface = Color(0xFF141416);
  static const Color glass = Color(0x14FFFFFF); // ~8% white
  static const Color glassIntense = Color(0x1FFFFFFF); // ~12%
  static const Color glassBorder = Color(0x2EFFFFFF); // ~18%
  static const Color accent = Color(0xFFE10600);
  static const Color accentSoft = Color(0x33E10600);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color danger = Color(0xFFFF453A);

  static BoxDecoration get scaffoldGradient => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.85),
          radius: 1.15,
          colors: [
            Color(0x55220000),
            background,
          ],
          stops: [0.0, 0.65],
        ),
      );

  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
    );

    final display = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
    final body = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: textPrimary,
        secondary: accent,
        onSecondary: textPrimary,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
        onError: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          fontSize: 56,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -1.5,
        ),
        displayMedium: display.displayMedium?.copyWith(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -1,
        ),
        displaySmall: display.displaySmall?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: display.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: display.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: body.bodyLarge?.copyWith(
          fontSize: 16,
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: body.bodyMedium?.copyWith(
          fontSize: 14,
          color: textSecondary,
          height: 1.45,
        ),
        bodySmall: body.bodySmall?.copyWith(
          fontSize: 12,
          color: textSecondary,
        ),
        labelLarge: body.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: textPrimary,
          disabledBackgroundColor: accent.withValues(alpha: 0.35),
          disabledForegroundColor: textPrimary.withValues(alpha: 0.7),
          elevation: 0,
          shadowColor: accent.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: glassBorder, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.7)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glass,
        selectedColor: accentSoft,
        side: const BorderSide(color: glassBorder),
        labelStyle: const TextStyle(color: textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1FFFFFFF),
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: glass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: glassBorder),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
      iconTheme: const IconThemeData(color: textPrimary),
    );
  }
}
