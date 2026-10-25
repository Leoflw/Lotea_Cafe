import 'dart:typed_data';
import '../repositories/repo_exception.dart';

enum ImageType {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  final String mime;
  final String extension;
  const ImageType(this.mime, this.extension);
}

/// Validación local de una imagen ANTES de pedir autorización y subirla.
/// El tipo se decide por los primeros bytes del archivo (no por la
/// extensión, que se puede falsear). El Worker repite estos límites del lado
/// del servidor: deben coincidir con `MAX_BYTES` y `ALLOWED_TYPES` en
/// cloudflare/imagekit-upload-auth/src/index.js.
class ImageValidation {
  static const maxBytes = 5 * 1024 * 1024;

  /// Lado máximo con el que se reduce cada foto al elegirla (ver
  /// [pickerMaxSide]) y calidad JPEG aplicada por `image_picker`.
  static const pickerMaxSide = 1600.0;
  static const pickerQuality = 80;

  static ImageType? detectarTipo(List<int> b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return ImageType.jpeg;
    if (b.length >= 8 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
        b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) {
      return ImageType.png;
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && // RIFF
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) { // WEBP
      return ImageType.webp;
    }
    return null;
  }

  /// Devuelve el tipo detectado o lanza [RepoException] de validación.
  static ImageType validar(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const RepoException(RepoErrorKind.validacion, 'La imagen está vacía. Elige otra.');
    }
    final tipo = detectarTipo(bytes);
    if (tipo == null) {
      throw const RepoException(RepoErrorKind.validacion, 'Formato no admitido. Usa una imagen JPEG, PNG o WebP.');
    }
    if (bytes.length > maxBytes) {
      throw const RepoException(RepoErrorKind.validacion, 'La imagen supera 5 MB. Elige una más liviana.');
    }
    return tipo;
  }
}
