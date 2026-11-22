import '../models/lot_deletion.dart';
import 'interest_request_repository.dart';
import 'quote_repository.dart';

/// Cuántas solicitudes de interés y cotizaciones están relacionadas con un café, para la
/// confirmación de «Eliminar café». Reúne los conteos exactos de cada repositorio
/// (`count()` por `sellerId` + `coffeeLotId`); no descarga documentos.
///
/// Si CUALQUIERA de los dos conteos falla (conexión, permisos) la excepción se propaga: nunca
/// se devuelve 0 en lugar de «no se pudo calcular».
class LotDeletionImpactCounter {
  final InterestRequestRepository _solicitudes;
  final QuoteRepository _cotizaciones;

  const LotDeletionImpactCounter({required InterestRequestRepository solicitudes, required QuoteRepository cotizaciones})
      : _solicitudes = solicitudes,
        _cotizaciones = cotizaciones;

  Future<LotDeletionImpact> contar({required String sellerId, required String coffeeLotId}) async {
    final resultados = await Future.wait<int>([
      _solicitudes.contarDeLote(sellerId: sellerId, coffeeLotId: coffeeLotId),
      _cotizaciones.contarDeLote(sellerId: sellerId, coffeeLotId: coffeeLotId),
    ]);
    return LotDeletionImpact(solicitudes: resultados[0], cotizaciones: resultados[1]);
  }
}
