import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/image_source.dart';
import 'fullscreen_image_viewer.dart';

/// Componente de imagen único para toda la app: centraliza la carga (asset,
/// archivo local o remota de ImageKit, según [imageProviderFor]), el placeholder, el
/// manejo de error, los bordes y el BoxFit. Si [ampliable] es true y hay
/// imágenes, al tocarla abre [FullscreenImageViewer] posicionado en
/// [indiceEnGaleria] de [galeria].
///
/// Regla de uso: en tarjetas cuyo toque ya navega a un detalle (listas,
/// swipe, solicitudes) se usa `ampliable: false` para no tener dos acciones
/// compitiendo; la galería se amplía dentro de las pantallas de detalle.
class AppImage extends StatelessWidget {
  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final List<String>? galeria;
  final int indiceEnGaleria;
  final bool ampliable;
  final IconData iconoPlaceholder;

  const AppImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.galeria,
    this.indiceEnGaleria = 0,
    this.ampliable = true,
    this.iconoPlaceholder = Icons.coffee_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final tieneImagen = path != null && path!.isNotEmpty;
    final imagenes = galeria ?? (tieneImagen ? [path!] : const <String>[]);

    // Para fotos de ImageKit se pide el tamaño que realmente se pinta (según
    // el ancho del widget y la densidad de pantalla). Sin ancho fijo (tarjetas
    // que ocupan todo el espacio) se pide un ancho estándar de 720 px.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final anchoPx = (width != null && width!.isFinite) ? (width! * dpr).ceil() : 720;
    final contenido = tieneImagen
        ? Image(
            image: imageProviderFor(path!, anchoPx: anchoPx),
            width: width,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.medium,
            // Mientras carga se muestra el mismo placeholder: nunca un hueco.
            frameBuilder: (context, child, frame, sync) =>
                (frame == null && !sync) ? _placeholder(cargando: true) : child,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : _placeholder();

    final imagen = ClipRRect(borderRadius: radius, child: contenido);
    if (!ampliable || imagenes.isEmpty || !tieneImagen) return imagen;

    return Semantics(
      button: true,
      label: 'Ampliar fotografía',
      child: GestureDetector(
        onTap: () => FullscreenImageViewer.abrir(context, images: imagenes, initialIndex: indiceEnGaleria),
        child: imagen,
      ),
    );
  }

  /// Placeholder diseñado (no un degradado con un ícono perdido): fondo
  /// cálido con textura de círculos suaves y el ícono centrado. Solo se usa
  /// cuando de verdad no hay fotografía.
  Widget _placeholder({bool cargando = false}) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8D5BC), Color(0xFFCDAE8A)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final lado = c.hasBoundedHeight ? c.maxHeight : (height ?? 80);
          final grande = lado >= 140;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: -lado * 0.15,
                bottom: -lado * 0.15,
                child: Container(
                  width: lado * 0.7,
                  height: lado * 0.7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.12)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconoPlaceholder, color: AppColors.coffeeMedium.withOpacity(cargando ? 0.35 : 0.6), size: (lado * 0.32).clamp(18.0, 56.0).toDouble()),
                  if (grande && !cargando) ...[
                    const SizedBox(height: 6),
                    const Text('Sin fotografía', style: TextStyle(color: AppColors.coffeeMedium, fontSize: 12)),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
