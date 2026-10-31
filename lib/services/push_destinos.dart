import '../repositories/interest_request_repository.dart';
import '../repositories/quote_repository.dart';
import '../repositories/repo_exception.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/quotes/quote_detail_screen.dart';
import 'push_navigation.dart';

/// Resuelve el destino de una notificación a su pantalla, comprobando antes que
/// el recurso existe y que la persona que tiene la sesión abierta participa en él.
/// Si no, devuelve null (la app avisa «Este contenido ya no está disponible»).
ResolverDestino resolverDestinoPush({
  required InterestRequestRepository conexiones,
  required QuoteRepository cotizaciones,
}) {
  return (destino, uid) async {
    try {
      switch (destino.ruta) {
        case PushRuta.chat:
          final c = await conexiones.obtener(destino.id);
          if (c == null || !c.esConexion) return null;
          if (uid != c.compradorId && uid != c.sellerId) return null;
          return ChatScreen(
            interestRequestId: c.id,
            otroNombre: uid == c.compradorId ? c.sellerNombre : c.compradorNombre,
          );
        case PushRuta.cotizacion:
          final q = await cotizaciones.observar(destino.id).first;
          if (q == null) return null;
          if (uid != q.compradorId && uid != q.sellerId) return null;
          return QuoteDetailScreen(quoteId: q.id);
      }
    } on RepoException catch (e) {
      if (e.tipo == RepoErrorKind.sinPermisos || e.tipo == RepoErrorKind.noEncontrado) return null;
      rethrow;
    }
  };
}
