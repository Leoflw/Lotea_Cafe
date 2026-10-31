import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta inspirada en café: tonos tierra, marrón tostado y verde cafetal.
class AppColors {
  static const Color coffeeDark = Color(0xFF3E2723);
  static const Color coffeeMedium = Color(0xFF6F4E37);
  static const Color coffeeLight = Color(0xFFD7B899);
  static const Color cream = Color(0xFFFBF3E7);
  static const Color leafGreen = Color(0xFF3F6C51);
  static const Color leafGreenLight = Color(0xFF6FA57C);
  static const Color danger = Color(0xFFD9534F);
  static const Color like = Color(0xFF3F6C51);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.coffeeMedium,
        primary: AppColors.coffeeMedium,
        secondary: AppColors.leafGreen,
        surface: AppColors.cream,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.dmSerifDisplay(
        fontSize: 26,
        color: AppColors.coffeeDark,
      ),
      titleLarge: GoogleFonts.nunito(
        fontWeight: FontWeight.w800,
        fontSize: 20,
        color: AppColors.coffeeDark,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.coffeeDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coffeeMedium,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.coffeeMedium,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.coffeeMedium, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.coffeeLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.coffeeMedium, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.coffeeMedium,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
