import '../data/codec.dart';
import 'cuenta_eliminada.dart';

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

  // Marcadores OPCIONALES (etapa 7.0, solo lectura): quién eliminó su cuenta. Hoy ningún proceso los
  // escribe; si no existen todo se comporta exactamente como antes. Solo cambian la PRESENTACIÓN:
  // `estado`, los UID y los ids no se tocan, así que el chat aceptado sigue siendo legible.
  final bool compradorEliminado;
  final bool sellerEliminado;
  final DateTime? anonimizadoEn;

  /// `estado` traía un valor que esta versión no conoce (p. ej. de una versión posterior). El enum
  /// conserva su valor de respaldo, pero este indicador impide tratarlo como una solicitud abierta.
  final bool estadoDesconocido;

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
    this.compradorEliminado = false,
    this.sellerEliminado = false,
    this.anonimizadoEn,
    this.estadoDesconocido = false,
  });

  static String idPara(String compradorId, String coffeeLotId) => '${compradorId}_$coffeeLotId';

  /// El chat existe solo para solicitudes aceptadas; su id es el de la solicitud.
  String get chatId => id;
  bool get esConexion => estado == EstadoSolicitud.aceptada;

  /// Solicitud pendiente REAL (un estado desconocido no cuenta como pendiente).
  bool get esPendienteAbierta => !estadoDesconocido && estado == EstadoSolicitud.pendiente;

  /// `true` si [raw] (el valor de `estado` de un documento) existe pero no es un estado conocido.
  static bool estadoEsDesconocido(Object? raw) => raw != null && !EstadoSolicitud.values.any((e) => e.name == raw);

  // Presentación con los marcadores de cuenta eliminada.
  String get compradorNombreVisible => compradorEliminado ? nombreCuentaEliminada : compradorNombre;
  String get sellerNombreVisible => sellerEliminado ? nombreCuentaEliminada : sellerNombre;
  String? get compradorCiudadVisible => compradorEliminado ? null : compradorCiudad;
  String? get compradorTipoVisible => compradorEliminado ? null : compradorTipo;

  /// Nombre de la OTRA parte vista por [uid] («Cuenta eliminada» si esa parte eliminó su cuenta).
  String nombreContraparte(String uid) => uid == compradorId ? sellerNombreVisible : compradorNombreVisible;

  /// «Cuenta eliminada» si la otra parte de [uid] eliminó su cuenta; si no, null.
  String? nombreSiContraparteEliminada(String? uid) {
    if (uid == null) return null;
    if (uid == compradorId && sellerEliminado) return nombreCuentaEliminada;
    if (uid == sellerId && compradorEliminado) return nombreCuentaEliminada;
    return null;
  }

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
      compradorEliminado: readBool(m['compradorEliminado']),
      sellerEliminado: readBool(m['sellerEliminado']),
      anonimizadoEn: readDate(m['anonimizadoEn']),
      estadoDesconocido: estadoEsDesconocido(m['estado']),
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
