import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'fullscreen_image_viewer.dart';

/// Componente de imagen único para toda la app: centraliza carga desde
/// archivo local, placeholder, manejo de error, bordes y BoxFit. Si se le
/// pasa [galeria], al tocarla abre [FullscreenImageViewer] posicionado en
/// [indiceEnGaleria] — así una miniatura siempre abre la galería completa
/// desde la imagen correcta. Preparado para imagen remota en el futuro:
/// bastaría con añadir una rama `Image.network` cuando `esRemota` sea true.
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
    this.iconoPlaceholder = Icons.coffee,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final imagenes = galeria ?? (path != null ? [path!] : const <String>[]);

    Widget contenido;
    if (path == null || path!.isEmpty) {
      contenido = _placeholder();
    } else {
      contenido = Image.file(
        File(path!),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    final imagen = ClipRRect(borderRadius: radius, child: contenido);

    if (!ampliable || imagenes.isEmpty) return imagen;

    return GestureDetector(
      onTap: () => FullscreenImageViewer.abrir(context, images: imagenes, initialIndex: indiceEnGaleria),
      child: imagen,
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.coffeeLight,
      child: Icon(iconoPlaceholder, color: Colors.white, size: (height ?? 80) * 0.4),
    );
  }
}
