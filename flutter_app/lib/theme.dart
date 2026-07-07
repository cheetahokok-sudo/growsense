// ══════════════════════════════════════════════════════════════════
// GrowSense design tokens — Dart mirror of design-tokens.css.
// The CSS file remains the source of truth; when a value changes
// there, change it here too. Names match the CSS variables 1:1
// (--accent → GsColors.accent) so cross-referencing stays trivial.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class GsColors {
  static const bg = Color(0xFFF6F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEEF0EC);
  static const border = Color(0x14141E19); // rgba(20,30,25,0.08)
  static const border2 = Color(0x24141E19); // rgba(20,30,25,0.14)
  static const text = Color(0xFF131613);
  static const text2 = Color(0xFF5C655C);
  static const text3 = Color(0xFF95A092);
  static const ink = Color(0xFF1F2B22);
  static const accent = Color(0xFF2F6B4F);
  static const accentLight = Color(0xFFE1EEE5);
  static const accentDark = Color(0xFF1B4632);
  static const deepGreen = Color(0xFF0E2A20);
  static const measured = Color(0xFF2A5C8A);
  static const measuredLight = Color(0xFFE3EDF6);
  static const measuredDark = Color(0xFF1C3F61);
  static const estimated = Color(0xFF9C7A3D);
  static const estimatedLight = Color(0xFFF4ECDB);
  static const estimatedDark = Color(0xFF6B5226);
  static const flag = Color(0xFFA23B3B);
  static const flagLight = Color(0xFFF6E4E2);
  static const flagDark = Color(0xFF6E2424);
}

abstract final class GsRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

/// --shadow from design-tokens.css
const gsShadow = [
  BoxShadow(color: Color(0x0D141E19), offset: Offset(0, 1), blurRadius: 2),
  BoxShadow(color: Color(0x08141E19), offset: Offset(0, 2), blurRadius: 8),
];

/// Theme is locale-aware: Thai gets Sarabun (the brand's Thai face),
/// Arabic gets Noto Sans Arabic; everything else uses Inter.
ThemeData buildGrowSenseTheme([String localeCode = 'en']) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: GsColors.accent,
      primary: GsColors.accent,
      surface: GsColors.bg,
      error: GsColors.flag,
    ),
    scaffoldBackgroundColor: GsColors.bg,
  );
  final localizedText = switch (localeCode) {
    'th' => GoogleFonts.sarabunTextTheme(base.textTheme),
    'ar' => GoogleFonts.notoSansArabicTextTheme(base.textTheme),
    _ => GoogleFonts.interTextTheme(base.textTheme),
  };
  final textTheme = localizedText.apply(
    bodyColor: GsColors.text,
    displayColor: GsColors.text,
  );
  return base.copyWith(
    textTheme: textTheme,
    // Light topbar matching the PWA's .topbar (logo on bg, subtle
    // bottom border comes from the shell).
    appBarTheme: const AppBarTheme(
      backgroundColor: GsColors.bg,
      foregroundColor: GsColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: GsColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GsRadius.md),
        side: const BorderSide(color: GsColors.border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GsColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GsRadius.md),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GsColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GsRadius.md),
        borderSide: const BorderSide(color: GsColors.border2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GsRadius.md),
        borderSide: const BorderSide(color: GsColors.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GsRadius.md),
        borderSide: const BorderSide(color: GsColors.accent, width: 1.5),
      ),
    ),
    // Label styles derive from the locale-aware text theme so Thai /
    // Arabic glyphs render in the right font instead of tofu boxes.
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: GsColors.surface,
      selectedItemColor: GsColors.accent,
      unselectedItemColor: GsColors.text3,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: textTheme.bodySmall
          ?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.bodySmall?.copyWith(fontSize: 11),
    ),
  );
}
