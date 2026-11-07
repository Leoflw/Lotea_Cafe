import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de Lotea Café: tierra, tostado y verde cafetal.
///
/// Reglas de uso (para mantener la identidad sin saturar):
/// * **Marrón tostado** ([coffeeMedium]): acción principal, selección y
///   elementos de marca. Es el color "protagonista" de la interfaz.
/// * **Verde cafetal** ([leafGreen]): estados positivos (disponible,
///   verificado, aceptado) y acentos secundarios. No se usa para botones
///   principales.
/// * **Marrón profundo** ([coffeeDark]): texto principal y títulos.
/// * **Tierra clara / crema** ([coffeeLight], [cream]): fondos, bordes
///   decorativos y superficies. [coffeeLight] NO sirve para texto ni para el
///   borde de un control interactivo (contraste ~1.9:1); para eso existe
///   [outlineStrong].
///
/// Los nombres y valores originales se conservan porque las pantallas ya los
/// usan; el único valor ajustado es [danger] (ver nota en su definición).
class AppColors {
  AppColors._();

  // --- Marca (sin cambios de nombre) -------------------------------------
  static const Color coffeeDark = Color(0xFF3E2723);
  static const Color coffeeMedium = Color(0xFF6F4E37);
  static const Color coffeeLight = Color(0xFFD7B899);
  static const Color cream = Color(0xFFFBF3E7);
  static const Color leafGreen = Color(0xFF3F6C51);
  static const Color leafGreenLight = Color(0xFF6FA57C);

  /// Antes #D9534F (contraste 3.6:1 sobre crema y 3.96:1 con texto blanco,
  /// por debajo de 4.5:1 en texto pequeño). #B3382F mantiene el rojo cálido
  /// y alcanza 5.4:1 sobre crema y 5.96:1 con texto blanco.
  static const Color danger = Color(0xFFB3382F);
  static const Color like = Color(0xFF3F6C51);

  // --- Neutros cálidos (reemplazan a Colors.grey en la etapa 2) -----------
  /// Texto principal. Igual que [coffeeDark].
  static const Color ink = coffeeDark;

  /// Texto secundario: subtítulos y descripciones. 6.3:1 sobre crema.
  static const Color inkSoft = Color(0xFF6B5547);

  /// Texto auxiliar: etiquetas, ayudas, iconos inactivos. 5.0:1 sobre crema.
  static const Color inkMuted = Color(0xFF7D6455);

  /// Superficies: tarjetas y campos sobre el fondo crema.
  static const Color surface = Colors.white;

  /// Superficie cálida para áreas agrupadas (chips, fondos de sección).
  static const Color surfaceWarm = Color(0xFFF3E8D7);

  /// Línea suave decorativa (divisores, bordes de tarjeta). No para controles.
  static const Color outline = Color(0xFFE8D9C4);

  /// Borde de controles interactivos (campos, botón secundario).
  /// 3.3:1 sobre blanco, el mínimo recomendado para componentes de interfaz.
  static const Color outlineStrong = Color(0xFFA38870);

  // --- Semánticos ---------------------------------------------------------
  /// Éxito (acción completada, aceptado). Mismo verde de marca.
  static const Color success = leafGreen;
  static const Color successContainer = Color(0xFFE3EEE5);

  /// Advertencia / pendiente. 5.4:1 sobre crema. Evita el amarillo puro,
  /// que no tiene contraste sobre fondos claros.
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFFBEBCB);

  /// Información. Es el azul que ya usaban las cotizaciones (4.9:1).
  static const Color info = Color(0xFF2F6F9F);
  static const Color infoContainer = Color(0xFFDFEAF3);

  /// Error: usa [danger].
  static const Color error = danger;
  static const Color errorContainer = Color(0xFFF8E1DE);

  /// Error sobre fondos oscuros (onboarding): #B3382F no tiene contraste
  /// sobre café profundo; este tono claro sí (más de 8:1).
  static const Color errorOnDark = Color(0xFFFFB4A8);
}

/// Escala de espaciado compartida (múltiplos de 4).
/// Uso previsto desde la etapa 2; en la etapa 1 solo la define el tema.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Margen lateral estándar de las pantallas.
  static const double screen = 16;
}

/// Radios compartidos: 12 (controles), 16 (tarjetas y paneles),
/// 20 (hojas inferiores y elementos destacados). [pill] para chips.
class AppRadius {
  AppRadius._();
  static const double control = 12;
  static const double card = 16;
  static const double sheet = 20;
  static const double pill = 999;

  static BorderRadius get controlBorder => BorderRadius.circular(control);
  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get sheetBorder => BorderRadius.circular(sheet);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.coffeeMedium,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.coffeeMedium,
      onPrimary: Colors.white,
      primaryContainer: AppColors.surfaceWarm,
      onPrimaryContainer: AppColors.coffeeDark,
      secondary: AppColors.leafGreen,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.successContainer,
      onSecondaryContainer: AppColors.leafGreen,
      tertiary: AppColors.info,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.infoContainer,
      onTertiaryContainer: AppColors.info,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.danger,
      surface: AppColors.cream,
      onSurface: AppColors.coffeeDark,
      onSurfaceVariant: AppColors.inkSoft,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: AppColors.surfaceWarm,
      surfaceContainerHigh: AppColors.surfaceWarm,
      surfaceContainerHighest: AppColors.surfaceWarm,
      outline: AppColors.outlineStrong,
      outlineVariant: AppColors.outline,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
    );

    final textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.coffeeDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coffeeMedium,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.outline,
          disabledForegroundColor: AppColors.inkMuted,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBorder),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.coffeeMedium,
          disabledForegroundColor: AppColors.inkMuted,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.coffeeMedium, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBorder),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.coffeeMedium,
          disabledForegroundColor: AppColors.inkMuted,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBorder),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        floatingLabelStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.coffeeMedium),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.inkSoft,
        suffixIconColor: AppColors.inkSoft,
        border: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide: const BorderSide(color: AppColors.outlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide: const BorderSide(color: AppColors.outlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide:
              const BorderSide(color: AppColors.coffeeMedium, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.controlBorder,
          borderSide: const BorderSide(color: AppColors.outline),
        ),
      ),
      // Tarjetas planas con borde suave en lugar de sombra marcada.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      // Mensajes: todos flotan, con esquinas de 12 y texto claro sobre café
      // profundo. Los que fijan un color semántico (verde éxito, rojo error)
      // conservan ese fondo, pero comparten forma, margen y tipografía.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.coffeeDark,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.coffeeLight,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlBorder),
      ),
      // Diálogos: superficie blanca, esquinas de 20, título en la escala.
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetBorder),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 18),
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.coffeeMedium,
        unselectedItemColor: AppColors.inkMuted,
        selectedLabelStyle:
            textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: textTheme.labelSmall,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  /// Escala tipográfica de cinco niveles. Nunito para la interfaz y
  /// DM Serif Display solo para el titular.
  ///
  /// 1. Titular (serif): [TextTheme.headlineSmall] 26.
  /// 2. Título: [TextTheme.titleLarge] 20, w800 (también lo usa la marca).
  /// 3. Subtítulo: [TextTheme.titleMedium] 16 y [TextTheme.titleSmall] 14, w700.
  /// 4. Contenido: [TextTheme.bodyLarge] 16, [TextTheme.bodyMedium] 14.
  /// 5. Auxiliar: [TextTheme.bodySmall] 12.5 (el tamaño más usado hoy en las
  ///    pantallas para texto de apoyo) y [TextTheme.labelSmall] 11.5 para
  ///    etiquetas mínimas. Etiquetas de botón: [TextTheme.labelLarge] 14.
  static TextTheme _textTheme(TextTheme base) {
    final nunito = GoogleFonts.nunitoTextTheme(base).apply(
      bodyColor: AppColors.coffeeDark,
      displayColor: AppColors.coffeeDark,
    );

    return nunito.copyWith(
      headlineSmall: GoogleFonts.dmSerifDisplay(
        fontSize: 26,
        height: 1.2,
        color: AppColors.coffeeDark,
      ),
      titleLarge: nunito.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 20,
        height: 1.25,
        color: AppColors.coffeeDark,
      ),
      titleMedium: nunito.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        height: 1.3,
        color: AppColors.coffeeDark,
      ),
      titleSmall: nunito.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        height: 1.3,
        color: AppColors.coffeeDark,
      ),
      bodyLarge: nunito.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: nunito.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: nunito.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.35,
        color: AppColors.inkSoft,
      ),
      labelLarge: nunito.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      labelMedium: nunito.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
        color: AppColors.inkSoft,
      ),
      labelSmall: nunito.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 11.5,
        color: AppColors.inkMuted,
      ),
    );
  }
}
