import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/coffee_lot.dart';
import '../models/interest_request.dart';
import 'repo_exception.dart';

/// Colección `interestRequests/{compradorId}_{coffeeLotId}`.
class InterestRequestRepository {
  final FirebaseFirestore _db;
  InterestRequestRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('interestRequests');

  InterestRequest _desde(DocumentSnapshot<Map<String, dynamic>> d) => InterestRequest.fromMap(d.id, d.data() ?? {});

  Stream<List<InterestRequest>> observarEnviadas(String compradorId) {
    final s = _col
        .where('compradorId', isEqualTo: compradorId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => q.docs.map(_desde).toList());
    return traducirErrores(s);
  }

  Stream<List<InterestRequest>> observarRecibidas(String sellerId) {
    final s = _col
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => q.docs.map(_desde).toList());
    return traducirErrores(s);
  }

  Stream<InterestRequest?> observar(String id) {
    return traducirErrores(_col.doc(id).snapshots().map((d) => d.exists ? _desde(d) : null));
  }

  Future<InterestRequest?> obtener(String id) => guardar(() async {
        final d = await _col.doc(id).get();
        return d.exists ? _desde(d) : null;
      });

  /// Crea la solicitud del comprador. El id determinista hace que dos toques
  /// seguidos no generen dos solicitudes. Si existía una RECHAZADA, se
  /// reabre como pendiente; si existe una activa se lanza `duplicado`.
  Future<InterestRequest> crear({required AppUser comprador, required CoffeeLot lote, String? mensaje}) {
    final id = InterestRequest.idPara(comprador.uid, lote.id);
    final solicitud = InterestRequest(
      id: id,
      compradorId: comprador.uid,
      sellerId: lote.sellerId,
      coffeeLotId: lote.id,
      mensaje: (mensaje == null || mensaje.trim().isEmpty) ? null : mensaje.trim(),
      compradorNombre: comprador.nombre,
      compradorCiudad: comprador.ciudad,
      compradorTipo: comprador.tipoComprador?.label,
      sellerNombre: lote.sellerNombreMarca,
      loteNombre: lote.nombre,
      loteFoto: lote.fotoPrincipal,
      lotePrecioCOP: lote.precioCOP,
      loteUnidad: lote.unidad,
    );
    return guardar(() async {
      final ref = _col.doc(id);
      await _db.runTransaction((tx) async {
        final actual = await tx.get(ref);
        if (!actual.exists) {
          tx.set(ref, {
            ...solicitud.toCreateMap(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        final estado = readEstado(actual.data());
        if (estado == EstadoSolicitud.rechazada) {
          tx.update(ref, {
            'estado': EstadoSolicitud.pendiente.name,
            'mensaje': solicitud.mensaje,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }
        throw RepoException(
          RepoErrorKind.duplicado,
          estado == EstadoSolicitud.aceptada
              ? 'Ya tienes una conexión comercial con este vendedor para este café.'
              : 'Ya has enviado una solicitud para este café. Espera la respuesta del vendedor.',
        );
      });
      return solicitud;
    });
  }

  static EstadoSolicitud readEstado(Map<String, dynamic>? data) {
    final v = data?['estado'];
    for (final e in EstadoSolicitud.values) {
      if (e.name == v) return e;
    }
    return EstadoSolicitud.pendiente;
  }

  /// Marca como leído el chat de la conexión PARA QUIEN LO ABRE: cada
  /// participante solo escribe su propio campo (`leidoComprador` o
  /// `leidoVendedor`); el estado de la otra persona no se toca. La marca vive
  /// en Firestore, así que persiste entre sesiones y dispositivos.
  Future<void> marcarChatLeido(String solicitudId, {required bool esComprador}) => guardar(() async {
        await _col.doc(solicitudId).update({
          esComprador ? 'leidoComprador' : 'leidoVendedor': FieldValue.serverTimestamp(),
        });
      });

  /// El vendedor destinatario acepta o rechaza una solicitud PENDIENTE.
  Future<void> responder(String solicitudId, {required bool aceptar}) => guardar(() async {
        final ref = _col.doc(solicitudId);
        await _db.runTransaction((tx) async {
          final actual = await tx.get(ref);
          if (!actual.exists) throw const RepoException(RepoErrorKind.noEncontrado, 'La solicitud ya no existe.');
          if (readEstado(actual.data()) != EstadoSolicitud.pendiente) {
            throw const RepoException(RepoErrorKind.transicionInvalida, 'Esta solicitud ya fue respondida.');
          }
          tx.update(ref, {
            'estado': (aceptar ? EstadoSolicitud.aceptada : EstadoSolicitud.rechazada).name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      });
}
