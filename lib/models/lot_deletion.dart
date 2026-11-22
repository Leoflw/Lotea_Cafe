/// Estado de la solicitud `users/{uid}/pendingLotDeletions/{lotId}` que escribe el Worker
/// de limpieza (ver `cloudflare/imagekit-cleanup/src/lotes.js`). La app solo los LEE.
///
///   pendiente      la app pidió la eliminación; el Worker aún no la toma
///   procesando     el Worker la está ejecutando
///   errorTemporal  falló un paso; el Worker la reintenta solo (espera creciente)
///   fallido        agotó los reintentos; la app puede reabrirla (CoffeeLotRepository.eliminar)
///   completado     el lote ya se borró
///
/// Cualquier otro valor (por ejemplo «rechazado», que solo ocurre si el lote no era de quien lo
/// pidió) se ignora: ese café no está en proceso de eliminación.
enum EstadoEliminacionLote {
  pendiente,
  procesando,
  errorTemporal,
  fallido,
  completado;

  static EstadoEliminacionLote? desde(Object? valor) {
    for (final e in values) {
      if (e.name == valor) return e;
    }
    return null;
  }

  /// El café ya no está en el catálogo y el Worker lo está terminando de borrar.
  bool get enCurso => this == pendiente || this == procesando || this == errorTemporal;

  /// El Worker agotó los reintentos; hace falta que la persona vuelva a pedirlo.
  bool get fallo => this == fallido;

  /// El lote ya se borró (o está a punto de desaparecer de Firestore).
  bool get terminado => this == completado;
}

/// Negociaciones relacionadas con UN café, contadas con agregaciones `count()` (no con las
/// listas de ActivityProvider, que están limitadas a 100 documentos).
class LotDeletionImpact {
  final int solicitudes;
  final int cotizaciones;
  const LotDeletionImpact({required this.solicitudes, required this.cotizaciones});
}
