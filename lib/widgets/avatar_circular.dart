import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_logic.dart';
import '../utils/image_source.dart';

/// Círculo con la foto de perfil (de ImageKit) o, si no hay foto, mientras
/// carga o si la imagen falla, la INICIAL del nombre. Nunca deja un hueco ni
/// lanza una excepción por una URL rota.
///
/// Usa [imageProviderFor]: la foto se pide ya redimensionada con la
/// transformación de ImageKit (`tr=w-…,q-80`) según el tamaño pintado, y en
/// Firestore sigue guardada la URL original.
class AvatarCircular extends StatelessWidget {
  final String? fotoUrl;
  final String nombre;
  final double radius;
  final double fontSize;
  final FontWeight fontWeight;

  const AvatarCircular({
    super.key,
    required this.fotoUrl,
    required this.nombre,
    this.radius = 22,
    this.fontSize = 16,
    this.fontWeight = FontWeight.normal,
  });

  @override
  Widget build(BuildContext context) {
    final diametro = radius * 2;
    // Acepta URL remota o ruta local (vista previa de una foto recién elegida).
    // Qué foto corresponde a cada sesión lo decide AvatarLogic antes de llegar aquí.
    final texto = fotoUrl?.trim();
    final url = (texto == null || texto.isEmpty) ? null : texto;
    final inicial = SizedBox(
      width: diametro,
      height: diametro,
      child: Center(
        child: Text(
          AvatarLogic.inicial(nombre),
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: fontWeight),
        ),
      ),
    );

    Widget contenido = inicial;
    if (url != null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      contenido = Image(
        // La `key` por URL reinicia la carga cuando el vendedor cambia su foto.
        key: ValueKey(url),
        image: imageProviderFor(url, anchoPx: (diametro * dpr).ceil()),
        width: diametro,
        height: diametro,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        // Mientras carga y si falla se ve la inicial: nunca un hueco.
        frameBuilder: (context, child, frame, sync) => (frame == null && !sync) ? inicial : child,
        errorBuilder: (_, __, ___) => inicial,
      );
    }

    return Semantics(
      label: url != null ? 'Foto de $nombre' : 'Inicial de $nombre',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: diametro,
          height: diametro,
          decoration: const BoxDecoration(color: AppColors.coffeeLight, shape: BoxShape.circle),
          child: ClipOval(child: contenido),
        ),
      ),
    );
  }
}
