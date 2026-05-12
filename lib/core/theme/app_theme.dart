// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Brand colors
  static const Color primary = Color(0xFFE040FB);       // neon purple
  static const Color secondary = Color(0xFF00E5FF);     // neon cyan
  static const Color accent = Color(0xFFFF4081);        // neon pink
  static const Color background = Color(0xFF0D0D1A);    // deep dark
  static const Color surface = Color(0xFF1A1A2E);       // card dark
  static const Color surfaceVariant = Color(0xFF16213E);
  static const Color onSurface = Color(0xFFE8E8FF);
  static const Color success = Color(0xFF69FF47);
  static const Color warning = Color(0xFFFFD740);
  static const Color error = Color(0xFFFF5252);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: surface,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: onSurface,
        error: error,
      ),
      scaffoldBackgroundColor: background,
      textTheme: GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.nunito(
          fontSize: 57,
          fontWeight: FontWeight.w800,
          color: onSurface,
          letterSpacing: -0.25,
        ),
        displayMedium: GoogleFonts.nunito(
          fontSize: 45,
          fontWeight: FontWeight.w800,
          color: onSurface,
        ),
        titleLarge: GoogleFonts.nunito(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        bodyLarge: GoogleFonts.nunito(fontSize: 16, color: onSurface),
        bodyMedium: GoogleFonts.nunito(fontSize: 14, color: onSurface),
        labelLarge: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: onSurface,
          letterSpacing: 0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A4A), width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: primary,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: GoogleFonts.nunito(color: Colors.white54),
        hintStyle: GoogleFonts.nunito(color: Colors.white30),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A4A),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: onSurface),
    );
  }
}
