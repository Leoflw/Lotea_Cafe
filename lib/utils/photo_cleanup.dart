/// Cálculo de qué fotos de ImageKit dejó de usar un documento al guardarse.
///
/// El `fileId` de ImageKit se guarda en los campos paralelos `*StoragePaths`
/// (`fotosStoragePaths`, `galeriaStoragePaths`, `fotoPrincipalStoragePath`). Los
/// documentos antiguos pueden tener ahí una cadena vacía: esas fotos NO se
/// pueden limpiar automáticamente porque no se sabe su identificador (no se
/// deduce de la URL).
class PhotoCleanup {
  PhotoCleanup._();

  /// Misma forma que exigen `firestore.rules` y el Worker de limpieza.
  static final RegExp _forma = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  static bool esFileIdValido(String id) => _forma.hasMatch(id);

  /// Ids (sin vacíos ni espacios) de una lista leída de Firestore.
  static List<String> idsDe(Object? lista) {
    if (lista is! List) return const <String>[];
    return <String>[
      for (final e in lista)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  }

  /// Ids de [previos] que ya no están en [actuales]: sin repetidos, sin vacíos y
  /// solo con forma de fileId. Una foto que se conserva NUNCA aparece aquí.
  static List<String> retirados({required Iterable<String> previos, required Iterable<String> actuales}) {
    final vigentes = actuales.map((e) => e.trim()).toSet();
    final vistos = <String>{};
    final salida = <String>[];
    for (final p in previos) {
      final id = p.trim();
      if (id.isEmpty || !esFileIdValido(id) || vigentes.contains(id) || !vistos.add(id)) continue;
      salida.add(id);
    }
    return salida;
  }
}
