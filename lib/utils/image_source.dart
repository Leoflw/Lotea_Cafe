import 'dart:io';
import 'package:flutter/widgets.dart';
import '../config/imagekit_config.dart';

/// Punto único que decide de dónde viene una imagen a partir de su ruta:
///  - `assets/...`    → recurso empaquetado (recursos de marca)
///  - `http(s)://...` → remota (fotos alojadas en ImageKit)
///  - cualquier otra ruta → archivo local recién elegido desde la galería
///
/// Si la foto es de ImageKit y se indica [anchoPx], se pide ya redimensionada
/// (ver [ImageKitUrls.optimizada]): una tarjeta de 60 px no descarga la foto
/// completa. En Firestore siempre queda la URL original, sin transformar.
ImageProvider imageProviderFor(String path, {int? anchoPx}) {
  if (path.startsWith('assets/')) return AssetImage(path);
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(anchoPx == null ? path : ImageKitUrls.optimizada(path, anchoPx));
  }
  return FileImage(File(path));
}

class ImageKitUrls {
  static const _anchosPermitidos = [160, 320, 480, 720, 1080, 1600];

  /// ¿Es una URL entregada por ImageKit? Reconoce `*.imagekit.io` y, si se
  /// configuró, el URL endpoint propio (dominios personalizados).
  static bool esImageKit(String url, {String urlEndpoint = ImageKitConfig.urlEndpointPorDefecto}) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    if (uri.host == 'imagekit.io' || uri.host.endsWith('.imagekit.io')) return true;
    return urlEndpoint.isNotEmpty && url.startsWith(urlEndpoint);
  }

  /// Redondea al ancho estándar siguiente para que muchas tarjetas compartan
  /// la misma URL (y la misma entrada de caché) y no haya una por cada píxel.
  static int anchoEstandar(num px) {
    for (final a in _anchosPermitidos) {
      if (px <= a) return a;
    }
    return _anchosPermitidos.last;
  }

  /// Añade la transformación de ImageKit `tr=w-<ancho>,q-80` (ancho acotado,
  /// calidad 80). Las URLs que no son de ImageKit, o que ya traen `tr`, se
  /// devuelven sin cambios.
  static String optimizada(String url, int anchoPx, {String urlEndpoint = ImageKitConfig.urlEndpointPorDefecto}) {
    if (!esImageKit(url, urlEndpoint: urlEndpoint)) return url;
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('tr') || url.contains('/tr:')) return url;
    final tr = 'tr=w-${anchoEstandar(anchoPx)},q-80';
    return url.contains('?') ? '$url&$tr' : '$url?$tr';
  }
}
