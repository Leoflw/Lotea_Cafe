import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/coffee_lot.dart';
import '../models/interest_request.dart';
import '../models/quote_request.dart';
import '../services/push_notifier.dart';
import 'repo_exception.dart';

/// Colección `quotes/{quoteId}` + subcolección `events` (historial).
///
/// Toda acción que cambia el estado pasa por [_transicionar]: dentro de una
/// transacción lee el documento, comprueba quién actúa, valida la transición
/// con [QuoteStateMachine] y escribe el cambio junto con su evento de
/// historial. Las reglas de Firestore repiten estas comprobaciones en el
/// servidor.
class QuoteRepository {
  final FirebaseFirestore _db;
  final NotificadorPush? _notificador;
  QuoteRepository({FirebaseFirestore? db, NotificadorPush? notificador})
      : _db = db ?? FirebaseFirestore.instance,
        _notificador = notificador;

  /// Avisa de un evento del historial YA confirmado por Firestore. No se espera y
  /// su fallo nunca afecta a la operación comercial que ya se guardó.
  void _avisar(String quoteId, String? eventoId) {
    final n = _notificador;
    if (n == null || eventoId == null) return;
    avisarSinEsperar(() => n.eventoDeCotizacion(quoteId: quoteId, eventoId: eventoId));
  }

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('quotes');

  QuoteRequest _desde(DocumentSnapshot<Map<String, dynamic>> d) => QuoteRequest.fromMap(d.id, d.data() ?? {});

  Stream<List<QuoteRequest>> observarComoComprador(String uid) {
    final s = _col
        .where('compradorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => q.docs.map(_desde).toList());
    return traducirErrores(s);
  }

  Stream<List<QuoteRequest>> observarComoVendedor(String uid) {
    final s = _col
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => q.docs.map(_desde).toList());
    return traducirErrores(s);
  }

  Stream<QuoteRequest?> observar(String id) {
    return traducirErrores(_col.doc(id).snapshots().map((d) => d.exists ? _desde(d) : null));
  }

  Stream<List<QuoteEvent>> observarEventos(String id) {
    final s = _col
        .doc(id)
        .collection('events')
        .orderBy('fecha')
        .snapshots()
        .map((q) => q.docs.map((d) => QuoteEvent.fromMap(d.id, d.data())).toList());
    return traducirErrores(s);
  }

  /// El comprador crea la solicitud de cotización dentro de una conexión
  /// ACEPTADA. [quoteId] lo genera la pantalla al abrirse: reintentar con el
  /// mismo id no crea duplicados (si ya existe, se devuelve ese documento).
  Future<QuoteRequest> crearSolicitud({
    required String quoteId,
    required InterestRequest conexion,
    required CoffeeLot lote,
    required String compradorUid,
    required double cantidad,
    required String unidad,
    String? lugarEntrega,
    String? comentario,
  }) async {
    final lugar = (lugarEntrega ?? '').trim();
    final coment = (comentario ?? '').trim();
    final error = QuoteValidator.solicitud(
      cantidad: cantidad,
      unidad: unidad,
      lugarEntrega: lugar,
      comentario: coment,
    );
    if (error != null) throw RepoException(RepoErrorKind.validacion, error);
    if (!conexion.esConexion) {
      throw const RepoException(RepoErrorKind.validacion, 'Solo puedes cotizar dentro de una conexión comercial aceptada.');
    }
    if (conexion.coffeeLotId != lote.id || conexion.sellerId != lote.sellerId) {
      throw const RepoException(RepoErrorKind.validacion, 'El café no corresponde a esta conexión comercial.');
    }
    if (conexion.compradorId != compradorUid) {
      throw const RepoException(RepoErrorKind.sinPermisos, 'Esta conexión no te pertenece.');
    }

    final quote = QuoteRequest(
      id: quoteId,
      interestRequestId: conexion.id,
      compradorId: compradorUid,
      sellerId: conexion.sellerId,
      coffeeLotId: lote.id,
      cantidad: cantidad,
      unidad: unidad,
      comentario: coment.isEmpty ? null : coment,
      lugarEntrega: lugar.isEmpty ? null : lugar,
      compradorNombre: conexion.compradorNombre,
      sellerNombre: lote.sellerNombreMarca.isEmpty ? conexion.sellerNombre : lote.sellerNombreMarca,
      loteNombre: lote.nombre,
      loteFoto: lote.fotoPrincipal,
    );

    // Id del evento del historial creado por la transacción que SÍ se confirmó. La
    // transacción puede ejecutarse más de una vez: el valor se reinicia en cada
    // ejecución y solo cuenta el de la última.
    String? eventoId;
    await guardar(() async {
      final ref = _col.doc(quoteId);
      await _db.runTransaction((tx) async {
        eventoId = null;
        final existente = await tx.get(ref);
        if (existente.exists) return; // reintento del mismo envío: no se vuelve a avisar
        tx.set(ref, {
          ...quote.toCreateMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final evento = ref.collection('events').doc();
        tx.set(evento, {
          'tipo': EventoCotizacion.solicitudCreada.name,
          'actor': ActorCotizacion.comprador.name,
          'actorId': compradorUid,
          'fecha': FieldValue.serverTimestamp(),
          'nota': coment.isEmpty ? null : coment,
        });
        eventoId = evento.id;
      });
    });
    _avisar(quoteId, eventoId); // después de que la transacción terminó bien
    return quote;
  }

  /// El vendedor destinatario envía (o reenvía tras una revisión) su oferta.
  Future<void> enviarOferta({
    required String quoteId,
    required String vendedorUid,
    required int precioUnitarioCOP,
    required int envioCOP,
    required String tiempoEntrega,
    DateTime? vigenciaHasta,
    String? condiciones,
    String? mensaje,
  }) async {
    final error = QuoteValidator.oferta(
      precioUnitarioCOP: precioUnitarioCOP,
      envioCOP: envioCOP,
      tiempoEntrega: tiempoEntrega,
      condiciones: condiciones,
      mensaje: mensaje,
      vigenciaHasta: vigenciaHasta,
    );
    if (error != null) throw RepoException(RepoErrorKind.validacion, error);

    await _transicionar(
      quoteId: quoteId,
      uid: vendedorUid,
      destino: EstadoCotizacion.ofertaEnviada,
      evento: EventoCotizacion.ofertaEnviada,
      construir: (actual) {
        final totales = QuoteCalculator.calcular(
          cantidad: actual.cantidad,
          precioUnitarioCOP: precioUnitarioCOP,
          envioCOP: envioCOP,
        );
        final version = (actual.oferta?.version ?? 0) + 1;
        final oferta = QuoteOffer(
          precioUnitarioCOP: precioUnitarioCOP,
          unidadPrecio: actual.unidad,
          subtotalCOP: totales.subtotalCOP,
          envioCOP: totales.envioCOP,
          totalCOP: totales.totalCOP,
          tiempoEntrega: tiempoEntrega.trim(),
          vigenciaHasta: vigenciaHasta,
          condiciones: (condiciones ?? '').trim(),
          mensaje: (mensaje ?? '').trim().isEmpty ? null : mensaje!.trim(),
          version: version,
        );
        return _Cambio(
          campos: {'oferta': oferta.toMap(), 'revisionComentario': null},
          nota: oferta.mensaje,
          totalCOP: totales.totalCOP,
          versionOferta: version,
        );
      },
    );
  }

  /// El vendedor rechaza una solicitud (sin enviar oferta).
  Future<void> rechazarSolicitud({required String quoteId, required String vendedorUid, String? motivo}) =>
      _transicionar(
        quoteId: quoteId,
        uid: vendedorUid,
        destino: EstadoCotizacion.solicitudRechazada,
        evento: EventoCotizacion.solicitudRechazada,
        construir: (_) => _Cambio(campos: const {}, nota: _nota(motivo)),
      );

  /// El comprador acepta la oferta. NO crea pedido, pago ni envío: solo
  /// deja registrado el acuerdo sobre las condiciones comerciales.
  Future<void> aceptarOferta({required String quoteId, required String compradorUid}) => _transicionar(
        quoteId: quoteId,
        uid: compradorUid,
        destino: EstadoCotizacion.ofertaAceptada,
        evento: EventoCotizacion.ofertaAceptada,
        construir: (actual) => _Cambio(
          campos: const {},
          totalCOP: actual.oferta?.totalCOP,
          versionOferta: actual.oferta?.version,
        ),
      );

  Future<void> rechazarOferta({required String quoteId, required String compradorUid, String? motivo}) =>
      _transicionar(
        quoteId: quoteId,
        uid: compradorUid,
        destino: EstadoCotizacion.ofertaRechazada,
        evento: EventoCotizacion.ofertaRechazada,
        construir: (actual) => _Cambio(
          campos: const {},
          nota: _nota(motivo),
          totalCOP: actual.oferta?.totalCOP,
          versionOferta: actual.oferta?.version,
        ),
      );

  Future<void> solicitarRevision({required String quoteId, required String compradorUid, required String comentario}) {
    final c = comentario.trim();
    if (c.isEmpty) {
      throw const RepoException(RepoErrorKind.validacion, 'Cuéntale al vendedor qué quieres ajustar.');
    }
    if (c.length > QuoteLimits.maxComentario) {
      throw const RepoException(RepoErrorKind.validacion, 'El comentario es demasiado largo.');
    }
    return _transicionar(
      quoteId: quoteId,
      uid: compradorUid,
      destino: EstadoCotizacion.revisionSolicitada,
      evento: EventoCotizacion.revisionSolicitada,
      construir: (actual) => _Cambio(
        campos: {'revisionComentario': c},
        nota: c,
        totalCOP: actual.oferta?.totalCOP,
        versionOferta: actual.oferta?.version,
      ),
    );
  }

  Future<void> cancelar({required String quoteId, required String compradorUid}) => _transicionar(
        quoteId: quoteId,
        uid: compradorUid,
        destino: EstadoCotizacion.cancelada,
        evento: EventoCotizacion.cancelada,
        construir: (_) => const _Cambio(campos: {}),
      );

  String? _nota(String? t) {
    final v = (t ?? '').trim();
    if (v.length > QuoteLimits.maxComentario) {
      throw const RepoException(RepoErrorKind.validacion, 'El comentario es demasiado largo.');
    }
    return v.isEmpty ? null : v;
  }

  Future<void> _transicionar({
    required String quoteId,
    required String uid,
    required EstadoCotizacion destino,
    required EventoCotizacion evento,
    required _Cambio Function(QuoteRequest actual) construir,
  }) async {
    // Id del evento de la transacción confirmada (se reinicia en cada ejecución).
    String? eventoId;
    await guardar(() async {
      final ref = _col.doc(quoteId);
      await _db.runTransaction((tx) async {
        eventoId = null;
        final snap = await tx.get(ref);
        if (!snap.exists) throw const RepoException(RepoErrorKind.noEncontrado, 'La cotización ya no existe.');
        final actual = _desde(snap);

        final ActorCotizacion actor;
        if (uid == actual.compradorId) {
          actor = ActorCotizacion.comprador;
        } else if (uid == actual.sellerId) {
          actor = ActorCotizacion.vendedor;
        } else {
          throw const RepoException(RepoErrorKind.sinPermisos, 'No participas en esta cotización.');
        }

        if (!QuoteStateMachine.puede(actual.estado, destino, actor)) {
          throw RepoException(
            RepoErrorKind.transicionInvalida,
            'Esta acción ya no es posible: la cotización está en estado «${actual.estado.corto}».',
          );
        }
        if (destino == EstadoCotizacion.ofertaAceptada && (actual.oferta?.estaVencida() ?? true)) {
          throw const RepoException(RepoErrorKind.transicionInvalida, 'La oferta está vencida o no existe. Pide una revisión.');
        }

        final cambio = construir(actual);
        tx.update(ref, {
          ...cambio.campos,
          'estado': destino.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final eventoRef = ref.collection('events').doc();
        tx.set(eventoRef, {
          'tipo': evento.name,
          'actor': actor.name,
          'actorId': uid,
          'fecha': FieldValue.serverTimestamp(),
          'nota': cambio.nota,
          'totalCOP': cambio.totalCOP,
          'versionOferta': cambio.versionOferta,
        });
        eventoId = eventoRef.id;
      });
    });
    _avisar(quoteId, eventoId); // después de que la transacción terminó bien
  }
}

class _Cambio {
  final Map<String, dynamic> campos;
  final String? nota;
  final int? totalCOP;
  final int? versionOferta;
  const _Cambio({required this.campos, this.nota, this.totalCOP, this.versionOferta});
}
