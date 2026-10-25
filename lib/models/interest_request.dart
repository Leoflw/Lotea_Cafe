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
  });

  static String idPara(String compradorId, String coffeeLotId) => '${compradorId}_$coffeeLotId';

  /// El chat existe solo para solicitudes aceptadas; su id es el de la solicitud.
  String get chatId => id;
  bool get esConexion => estado == EstadoSolicitud.aceptada;

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
    );
  }
}
