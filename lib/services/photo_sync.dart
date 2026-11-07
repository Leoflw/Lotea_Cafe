import 'dart:io';
import '../repositories/image_repository.dart';
import '../repositories/repo_exception.dart';

class PhotoSyncFailure {
  /// Ruta local de la foto que no se pudo subir.
  final String ruta;
  final RepoException error;
  const PhotoSyncFailure(this.ruta, this.error);
}

class PhotoSyncResult {
  /// URLs remotas de ImageKit de las fotos que SÍ están subidas, en el orden
  /// del formulario. Una foto fallida nunca aparece aquí.
  final List<String> urls;

  /// `fileId` de ImageKit de cada URL (misma posición que [urls]).
  final List<String> fileIds;

  /// Fotos locales que no se pudieron subir (solo con `continuarSiFalla`).
  final List<PhotoSyncFailure> fallidas;

  const PhotoSyncResult(this.urls, this.fileIds, [this.fallidas = const []]);

  bool get completo => fallidas.isEmpty;
}

/// Convierte la lista de fotos de un formulario (URLs ya subidas + archivos
/// locales recién elegidos) en URLs remotas. Solo sube lo que es local; lo
/// que ya es una URL se conserva sin volver a subirse.
class PhotoSync {
  static bool esLocal(String p) => !(p.startsWith('http://') || p.startsWith('https://') || p.startsWith('assets/'));
  static bool esRemota(String p) => p.startsWith('http://') || p.startsWith('https://');

  /// [idsPorUrl] relaciona cada URL ya subida con su `fileId` de ImageKit.
  ///
  /// - Con `continuarSiFalla: false` (perfil, publicación) el primer fallo se
  ///   relanza y nada se guarda.
  /// - Con `continuarSiFalla: true` (borradores) se siguen subiendo las demás
  ///   y los fallos se devuelven en [PhotoSyncResult.fallidas].
  ///
  /// [alSubir] se invoca apenas una foto queda subida: el formulario cambia la
  /// ruta local por la URL, así un reintento no sube dos veces la misma foto.
  static Future<PhotoSyncResult> sincronizar({
    required ImageRepository repo,
    required ImagePurpose proposito,
    required List<String> fotos,
    required Map<String, String> idsPorUrl,
    bool continuarSiFalla = false,
    void Function(String rutaLocal, String url)? alSubir,
    void Function(int hechas, int total, double progresoActual)? alProgresar,
  }) async {
    final urls = <String>[];
    final ids = <String>[];
    final fallidas = <PhotoSyncFailure>[];
    final total = fotos.where(esLocal).length;
    var hechas = 0;
    for (final f in List<String>.of(fotos)) {
      if (!esLocal(f)) {
        if (esRemota(f)) {
          urls.add(f);
          ids.add(idsPorUrl[f] ?? '');
        }
        continue;
      }
      try {
        final subida = await repo.subir(
          proposito: proposito,
          archivo: File(f),
          alProgresar: (p) => alProgresar?.call(hechas, total, p),
        );
        idsPorUrl[subida.url] = subida.fileId;
        urls.add(subida.url);
        ids.add(subida.fileId);
        alSubir?.call(f, subida.url);
        hechas++;
        alProgresar?.call(hechas, total, 0);
      } on RepoException catch (e) {
        if (!continuarSiFalla) rethrow;
        fallidas.add(PhotoSyncFailure(f, e));
      }
    }
    return PhotoSyncResult(urls, ids, fallidas);
  }
}
