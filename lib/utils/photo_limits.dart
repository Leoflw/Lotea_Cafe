/// Límites de fotografías y sus mensajes. Es el ÚNICO lugar de la app donde
/// viven los números: pantallas, repositorios y pruebas los leen de aquí.
///
/// Los mismos valores están en `firestore.rules` (función `photoCountOk` y
/// sus llamadas). La prueba `test/photo_limits_test.dart` lee ese archivo y
/// falla si dejan de coincidir.
///
/// Política con datos antiguos (documentos creados con los límites de 10 y 12):
/// NO se recortan ni se migran. Un documento con más fotos que el máximo
/// puede seguir guardándose con la misma cantidad o con menos, de modo que su
/// dueño edite el resto de la información y reduzca las fotos cuando quiera,
/// pero nunca puede AUMENTAR su cantidad por encima del máximo
/// (ver [validarCantidad]).
class PhotoLimits {
  PhotoLimits._();

  /// Fotos por café (la primera es la principal).
  static const int maxCafe = 5;

  /// Fotos ADICIONALES de la galería de marca. La foto principal de la marca
  /// es independiente y no cuenta aquí.
  static const int maxGaleriaMarca = 6;

  static bool puedeAgregar(int actuales, int max) => actuales < max;

  static int espaciosLibres(int actuales, int max) => actuales >= max ? 0 : max - actuales;

  /// Documento antiguo con más fotos que el máximo actual.
  static bool excedeMaximo(int actuales, int max) => actuales > max;

  static String contadorCafe(int n) => '$n de $maxCafe fotos';
  static String contadorGaleria(int n) => '$n de $maxGaleriaMarca fotos de galería';

  static String mensajeCafeLleno() =>
      'Ya tienes $maxCafe fotos, el máximo por café. Quita una (toca la ✕ de su esquina) para poder agregar otra.';
  static String mensajeGaleriaLlena() =>
      'Ya tienes $maxGaleriaMarca fotos en la galería, el máximo. Quita una (toca la ✕ de su esquina) para poder agregar otra.';

  static String avisoCafeExcedido(int n) =>
      'Este café tiene $n fotos, más que el máximo actual ($maxCafe). Puedes conservarlas o quitar algunas, pero no agregar más hasta bajar de $maxCafe.';
  static String avisoGaleriaExcedida(int n) =>
      'Tu galería tiene $n fotos, más que el máximo actual ($maxGaleriaMarca). Puedes conservarlas o quitar algunas, pero no agregar más hasta bajar de $maxGaleriaMarca.';

  /// Mensaje cuando se eligieron más fotos de las que caben: se agregan las
  /// primeras y el resto se descarta.
  static String mensajeSeleccionRecortada({required int agregadas, required int descartadas, required int max, required bool galeria}) {
    final donde = galeria ? 'en la galería' : 'por café';
    final agregadasTxt = agregadas == 0
        ? 'No se agregó ninguna foto'
        : (agregadas == 1 ? 'Se agregó 1 foto' : 'Se agregaron $agregadas fotos');
    final descartadasTxt = descartadas == 1 ? 'otra quedó fuera' : '$descartadas quedaron fuera';
    return '$agregadasTxt y $descartadasTxt: el máximo es $max $donde. Quita alguna foto para liberar espacio.';
  }

  /// Devuelve el motivo por el que NO se puede guardar una lista con [nuevo]
  /// fotos, o `null` si se puede.
  ///
  /// - Dentro del máximo: siempre se puede.
  /// - Por encima del máximo: solo si la cantidad NO crece respecto de la que
  ///   ya había guardada ([previo]); así un documento antiguo se puede editar y
  ///   reducir, pero nunca crecer. Es la misma regla de `photoCountOk` en
  ///   `firestore.rules`.
  static String? validarCantidad({required int nuevo, required int max, int previo = 0, required bool galeria}) {
    if (nuevo <= max || nuevo <= previo) return null;
    return galeria
        ? 'La galería admite como máximo $max fotos adicionales.'
        : 'Cada café admite como máximo $max fotos.';
  }

  /// Parte [candidatas] en las que caben y las que no, respetando el espacio
  /// libre. Conserva el orden en que se eligieron.
  static ({List<T> aceptadas, int descartadas}) repartir<T>(int actuales, int max, List<T> candidatas) {
    final libres = espaciosLibres(actuales, max);
    final aceptadas = candidatas.take(libres).toList();
    return (aceptadas: aceptadas, descartadas: candidatas.length - aceptadas.length);
  }
}
