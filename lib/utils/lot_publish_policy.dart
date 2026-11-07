/// Reglas de fotos al guardar un café, separadas de la pantalla para poder
/// probarlas sin Flutter:
///  - Guardar un BORRADOR nunca exige foto.
///  - PUBLICAR exige al menos una foto subida con éxito y que no haya fotos
///    pendientes por una subida fallida (publicar a medias sorprendería al
///    vendedor).
class LotPublishPolicy {
  /// Devuelve el motivo por el que NO se puede continuar, o `null` si se puede.
  static String? motivoBloqueo({
    required bool publicar,
    required int fotosSubidas,
    required int fotosFallidas,
  }) {
    if (!publicar) return null;
    if (fotosFallidas > 0) {
      return fotosFallidas == 1
          ? 'No se pudo subir 1 foto. Reintenta antes de publicar.'
          : 'No se pudieron subir $fotosFallidas fotos. Reintenta antes de publicar.';
    }
    if (fotosSubidas < 1) return 'Agrega al menos una foto para publicar el café.';
    return null;
  }
}
