/// Reemplaza al antiguo "MatchModel". Representa el interés comercial de
/// un comprador por un lote de café concreto — NO se crea automáticamente
/// al deslizar: solo cuando el comprador confirma "Me interesa".
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
  final DateTime fecha;

  InterestRequest({
    required this.id,
    required this.compradorId,
    required this.sellerId,
    required this.coffeeLotId,
    this.mensaje,
    this.estado = EstadoSolicitud.pendiente,
    DateTime? fecha,
  }) : fecha = fecha ?? DateTime.now();

  /// El chat solo se habilita una vez la solicitud está aceptada; se usa
  /// el propio id de la solicitud como id de sala de chat.
  String get chatId => id;
  bool get esConexion => estado == EstadoSolicitud.aceptada;

  InterestRequest copyWith({EstadoSolicitud? estado}) {
    return InterestRequest(
      id: id,
      compradorId: compradorId,
      sellerId: sellerId,
      coffeeLotId: coffeeLotId,
      mensaje: mensaje,
      estado: estado ?? this.estado,
      fecha: fecha,
    );
  }
}
