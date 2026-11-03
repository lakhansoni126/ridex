import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// RideX design tokens, modelled on Apple's Human Interface Guidelines.
///
/// * Semantic, brightness-aware colours (label / secondaryLabel / grouped
///   backgrounds) instead of hard-coded hex values.
/// * HIG text styles (Large Title 34 → Caption 2 11).
/// * 8pt spacing grid, 44pt minimum touch targets, 12pt card radius.
///
/// Read resolved values from widgets with `context.rx`.
class AppTheme {
  AppTheme._();

  /// Brand accent (#E53935), brightened slightly in dark mode for contrast.
  static const CupertinoDynamicColor accent =
      CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE53935),
    darkColor: Color(0xFFFF453A),
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = RxPalette.of(brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE53935),
      brightness: brightness,
    ).copyWith(
      primary: palette.accent,
      surface: palette.card,
      error: palette.destructive,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // iOS platform semantics everywhere: Cupertino page transitions with
      // edge swipe-back, bouncing scroll physics, iOS text selection.
      platform: TargetPlatform.iOS,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: palette.separator,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: palette.accent,
        scaffoldBackgroundColor: palette.background,
        barBackgroundColor: palette.bar,
        textTheme: CupertinoTextThemeData(
          primaryColor: palette.accent,
          textStyle: palette.body,
          navLargeTitleTextStyle: palette.largeTitle,
          navTitleTextStyle: palette.headline,
          actionTextStyle: palette.body.copyWith(color: palette.accent),
        ),
      ),
    );
  }
}

/// Resolved colour + type tokens for one brightness.
class RxPalette {
  RxPalette._(this.brightness);

  factory RxPalette.of(Brightness b) =>
      b == Brightness.dark ? _dark : _light;

  static final RxPalette _light = RxPalette._(Brightness.light);
  static final RxPalette _dark = RxPalette._(Brightness.dark);

  final Brightness brightness;
  bool get isDark => brightness == Brightness.dark;

  Color _pick(int light, int dark) => Color(isDark ? dark : light);

  // ── Colours (iOS system values) ──────────────────────────────────────────
  Color get accent => _pick(0xFFE53935, 0xFFFF453A);
  Color get accentTint => accent.withOpacity(isDark ? 0.22 : 0.12);
  Color get onAccent => const Color(0xFFFFFFFF);

  Color get background => _pick(0xFFF2F2F7, 0xFF000000);
  Color get card => _pick(0xFFFFFFFF, 0xFF1C1C1E);
  Color get cardElevated => _pick(0xFFFFFFFF, 0xFF2C2C2E);
  Color get bar => _pick(0xF0F9F9F9, 0xF01D1D1D);
  Color get fill => _pick(0x1F787880, 0x3D787880);
  Color get fillSecondary => _pick(0x14787880, 0x29787880);

  Color get label => _pick(0xFF000000, 0xFFFFFFFF);
  Color get secondaryLabel => _pick(0x993C3C43, 0x99EBEBF5);
  Color get tertiaryLabel => _pick(0x4D3C3C43, 0x4DEBEBF5);
  Color get separator => _pick(0x4A3C3C43, 0x99545458);

  Color get destructive => _pick(0xFFFF3B30, 0xFFFF453A);
  Color get success => _pick(0xFF34C759, 0xFF30D158);
  Color get warning => _pick(0xFFFF9500, 0xFFFF9F0A);
  Color get info => _pick(0xFF007AFF, 0xFF0A84FF);
  Color get indigo => _pick(0xFF5856D6, 0xFF5E5CE6);
  Color get teal => _pick(0xFF30B0C7, 0xFF40C8E0);
  Color get gray => _pick(0xFF8E8E93, 0xFF8E8E93);

  // ── Typography (HIG text styles) ─────────────────────────────────────────
  TextStyle _t(double size, FontWeight w, {double? spacing, Color? color}) =>
      TextStyle(
        inherit: false,
        fontSize: size,
        fontWeight: w,
        letterSpacing: spacing,
        height: 1.25,
        color: color ?? label,
        decoration: TextDecoration.none,
        textBaseline: TextBaseline.alphabetic,
      );

  TextStyle get largeTitle => _t(34, FontWeight.w700, spacing: 0.37);
  TextStyle get title1 => _t(28, FontWeight.w700, spacing: 0.36);
  TextStyle get title2 => _t(22, FontWeight.w700, spacing: 0.35);
  TextStyle get title3 => _t(20, FontWeight.w600, spacing: 0.38);
  TextStyle get headline => _t(17, FontWeight.w600, spacing: -0.41);
  TextStyle get body => _t(17, FontWeight.w400, spacing: -0.41);
  TextStyle get callout => _t(16, FontWeight.w400, spacing: -0.32);
  TextStyle get subheadline =>
      _t(15, FontWeight.w400, spacing: -0.24, color: secondaryLabel);
  TextStyle get footnote =>
      _t(13, FontWeight.w400, spacing: -0.08, color: secondaryLabel);
  TextStyle get caption =>
      _t(12, FontWeight.w400, color: secondaryLabel);
  TextStyle get caption2 =>
      _t(11, FontWeight.w400, spacing: 0.07, color: secondaryLabel);

  /// Tabular numerals for live gauges.
  TextStyle numeric(double size, {FontWeight weight = FontWeight.w600}) =>
      _t(size, weight, spacing: -0.5).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Spacing scale (8pt grid).
class RxSpace {
  RxSpace._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Inset grouped list horizontal margin.
  static const double inset = 20;
  static const double radius = 12;
  static const double radiusLarge = 16;
  static const double minTouch = 44;
}

extension RxContext on BuildContext {
  RxPalette get rx => RxPalette.of(
        CupertinoTheme.maybeBrightnessOf(this) ??
            MediaQuery.maybePlatformBrightnessOf(this) ??
            Brightness.light,
      );
}
