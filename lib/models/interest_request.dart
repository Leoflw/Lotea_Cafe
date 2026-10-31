import '../data/codec.dart';

/// Solicitud comercial de un comprador por un lote ("Me interesa").
/// Documento `interestRequests/{compradorId}_{coffeeLotId}`: el id
/// determinista impide duplicados activos para el mismo comprador y lote.
enum EstadoSolicitud { pendiente, aceptada, rechazada }

extension EstadoSolicitudX on EstadoSolicitud {
  String get label {
    switch (this) {
      case EstadoSolicitud.pendiente:
        return 'Pendiente';
      case EstadoSolicitud.aceptada:
        return 'Conexión comercial';
      case EstadoSolicitud.rechazada:
        return 'Rechazada';
    }
  }
}

class InterestRequest {
  final String id;
  final String compradorId;
  final String sellerId;
  final String coffeeLotId;
  final String? mensaje;
  final EstadoSolicitud estado;
  final DateTime? fecha;
  final DateTime? updatedAt;

  // Copias de visualización tomadas al crear la solicitud (para mostrar la
  // lista sin leer un documento por tarjeta). No son fuente de verdad.
  final String compradorNombre;
  final String? compradorCiudad;
  final String? compradorTipo;
  final String sellerNombre;
  final String loteNombre;
  final String? loteFoto;
  final double? lotePrecioCOP;
  final String? loteUnidad;

  // Estado de lectura del chat (solo existe en conexiones aceptadas). Cada
  // participante escribe SOLO su propio `leido…`; el último mensaje lo escribe
  // quien lo envía. Ver «Mensajes no leídos» en el README y firestore.rules.
  final DateTime? ultimoMensajeAt;
  final String? ultimoMensajeDe; // uid de quien envió el último mensaje
  final String? ultimoMensajeId; // id del documento de ese mensaje
  final DateTime? leidoComprador; // hasta cuándo leyó el comprador
  final DateTime? leidoVendedor; // hasta cuándo leyó el vendedor

  const InterestRequest({
    required this.id,
    required this.compradorId,
    required this.sellerId,
    required this.coffeeLotId,
    this.mensaje,
    this.estado = EstadoSolicitud.pendiente,
    this.fecha,
    this.updatedAt,
    this.compradorNombre = '',
    this.compradorCiudad,
    this.compradorTipo,
    this.sellerNombre = '',
    this.loteNombre = '',
    this.loteFoto,
    this.lotePrecioCOP,
    this.loteUnidad,
    this.ultimoMensajeAt,
    this.ultimoMensajeDe,
    this.ultimoMensajeId,
    this.leidoComprador,
    this.leidoVendedor,
  });

  static String idPara(String compradorId, String coffeeLotId) => '${compradorId}_$coffeeLotId';

  /// El chat existe solo para solicitudes aceptadas; su id es el de la solicitud.
  String get chatId => id;
  bool get esConexion => estado == EstadoSolicitud.aceptada;

  /// ¿Es [uid] el comprador o el vendedor de esta conexión?
  bool esParticipante(String uid) => uid.isNotEmpty && (uid == compradorId || uid == sellerId);

  /// Hasta cuándo ha leído el chat [uid] (su propio estado, independiente del
  /// de la otra persona). `null` si nunca lo abrió o si no es participante.
  DateTime? leidoPor(String uid) {
    if (uid == compradorId) return leidoComprador;
    if (uid == sellerId) return leidoVendedor;
    return null;
  }

  /// ¿Hay mensajes que [uid] RECIBIÓ y aún no ha leído?
  ///  - Los mensajes que envió el propio [uid] nunca cuentan como recibidos.
  ///  - Una persona ajena a la conexión nunca tiene mensajes sin leer.
  ///  - Sin mensajes registrados (conexiones anteriores a esta función) → no.
  bool tieneMensajesNoLeidos(String uid) {
    if (!esConexion || !esParticipante(uid)) return false;
    final de = ultimoMensajeDe;
    final cuando = ultimoMensajeAt;
    if (de == null || de.isEmpty || cuando == null) return false;
    if (de == uid) return false;
    final leido = leidoPor(uid);
    return leido == null || cuando.isAfter(leido);
  }

  Map<String, dynamic> toCreateMap() => {
        'compradorId': compradorId,
        'sellerId': sellerId,
        'coffeeLotId': coffeeLotId,
        'mensaje': mensaje,
        'estado': EstadoSolicitud.pendiente.name,
        'compradorNombre': compradorNombre,
        'compradorCiudad': compradorCiudad,
        'compradorTipo': compradorTipo,
        'sellerNombre': sellerNombre,
        'loteNombre': loteNombre,
        'loteFoto': loteFoto,
        'lotePrecioCOP': lotePrecioCOP,
        'loteUnidad': loteUnidad,
      };

  factory InterestRequest.fromMap(String id, Map<String, dynamic> m) {
    return InterestRequest(
      id: id,
      compradorId: readString(m['compradorId']) ?? '',
      sellerId: readString(m['sellerId']) ?? '',
      coffeeLotId: readString(m['coffeeLotId']) ?? '',
      mensaje: readString(m['mensaje']),
      estado: readEnum(EstadoSolicitud.values, m['estado'], EstadoSolicitud.pendiente),
      fecha: readDate(m['createdAt']),
      updatedAt: readDate(m['updatedAt']),
      compradorNombre: readString(m['compradorNombre']) ?? '',
      compradorCiudad: readString(m['compradorCiudad']),
      compradorTipo: readString(m['compradorTipo']),
      sellerNombre: readString(m['sellerNombre']) ?? '',
      loteNombre: readString(m['loteNombre']) ?? '',
      loteFoto: readString(m['loteFoto']),
      lotePrecioCOP: readDouble(m['lotePrecioCOP']),
      loteUnidad: readString(m['loteUnidad']),
      ultimoMensajeAt: _fechaServidor(m, 'ultimoMensajeAt'),
      ultimoMensajeDe: readString(m['ultimoMensajeDe']),
      ultimoMensajeId: readString(m['ultimoMensajeId']),
      leidoComprador: _fechaServidor(m, 'leidoComprador'),
      leidoVendedor: _fechaServidor(m, 'leidoVendedor'),
    );
  }

  /// Lee una marca de tiempo escrita con `serverTimestamp()`. Mientras el
  /// servidor no confirma la escritura, el campo existe pero aún no tiene
  /// valor: se usa la hora local como estimación para que el indicador no
  /// «parpadee» (p. ej. al marcar un chat como leído sin conexión).
  static DateTime? _fechaServidor(Map<String, dynamic> m, String campo) {
    final v = readDate(m[campo]);
    if (v != null) return v;
    return m.containsKey(campo) && m[campo] == null ? DateTime.now() : null;
  }
}
