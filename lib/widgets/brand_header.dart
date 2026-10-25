import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ruta única del símbolo de marca (grano de café con hoja, PNG transparente
/// y sin texto). Todas las pantallas lo usan a través de [LoteaBrandHeader].
const String kLoteaSymbolAsset = 'assets/branding/lotea_cafe_symbol.png';

/// Relación ancho/alto del PNG del símbolo (401 × 512). Se usa solo para
/// reservar el espacio horizontal; la imagen nunca se estira ni se deforma.
const double _kSymbolAspect = 401 / 512;

/// Encabezado de marca reutilizable: símbolo transparente + nombre
/// «Lotea Café» + eslogan «Descubre. Compara. Conecta.», todo compuesto con
/// widgets. No usa ninguna imagen con fondo incrustado, de modo que se integra
/// con el color de la pantalla donde se coloque.
///
/// Se reduce automáticamente (nunca se amplía) si no cabe en el ancho
/// disponible, por lo que no provoca desbordamientos en teléfonos pequeños.
class LoteaBrandHeader extends StatelessWidget {
  /// Muestra el eslogan debajo del nombre.
  final bool showTagline;

  /// Alto del símbolo en píxeles lógicos.
  final double symbolHeight;

  /// Tamaño de fuente del nombre «Lotea Café».
  final double nameSize;

  /// `true` para fondos oscuros (texto crema); `false` para fondos claros.
  final bool dark;

  /// Posición del bloque dentro del ancho disponible (centrado por defecto).
  final AlignmentGeometry alignment;

  const LoteaBrandHeader({
    super.key,
    this.showTagline = true,
    this.symbolHeight = 76,
    this.nameSize = 36,
    this.dark = false,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameColor = dark ? AppColors.cream : AppColors.coffeeDark;
    final taglineColor = dark ? AppColors.coffeeLight : AppColors.coffeeMedium;

    final nameStyle = (textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: nameSize,
      height: 1.05,
      letterSpacing: -0.4,
      color: nameColor,
    );
    final taglineStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: nameSize * 0.34,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.3,
      color: taglineColor,
    );

    return Semantics(
      label: showTagline ? 'Lotea Café. Descubre. Compara. Conecta.' : 'Lotea Café',
      child: ExcludeSemantics(
        child: Align(
          alignment: alignment,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: symbolHeight * _kSymbolAspect,
                  height: symbolHeight,
                  child: Image.asset(kLoteaSymbolAsset, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
                SizedBox(width: symbolHeight * 0.2),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lotea Café', style: nameStyle, maxLines: 1, softWrap: false),
                    if (showTagline) ...[
                      SizedBox(height: nameSize * 0.08),
                      Text('Descubre. Compara. Conecta.', style: taglineStyle, maxLines: 1, softWrap: false),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla de espera con la marca (restauración de sesión, carga de perfil).
class BrandSplash extends StatelessWidget {
  final String? mensaje;
  const BrandSplash({super.key, this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoteaBrandHeader(symbolHeight: 84, nameSize: 38),
            const SizedBox(height: 28),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.coffeeMedium)),
            if (mensaje != null) ...[
              const SizedBox(height: 14),
              Text(mensaje!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
