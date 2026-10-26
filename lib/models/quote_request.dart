/// Solicitud de cotización dentro de una conexión comercial ya establecida.
/// Deja preparada la arquitectura para el flujo futuro:
/// Cotización → Pedido → Pago → Envío → Entrega (sección 12-13 del plan).
enum EstadoCotizacion { pendiente, respondida, aceptada, rechazada }

extension EstadoCotizacionX on EstadoCotizacion {
  String get label {
    switch (this) {
      case EstadoCotizacion.pendiente:
        return 'Pendiente';
      case EstadoCotizacion.respondida:
        return 'Respondida';
      case EstadoCotizacion.aceptada:
        return 'Aceptada';
      case EstadoCotizacion.rechazada:
        return 'Rechazada';
    }
  }
}

class QuoteRequest {
  final String id;
  final String interestRequestId; // conexión comercial a la que pertenece
  final String compradorId;
  final String sellerId;
  final String coffeeLotId;
  final double cantidad;
  final String unidad;
  final String? comentario;
  final String? lugarEntrega;
  final EstadoCotizacion estado;
  final DateTime fecha;

  QuoteRequest({
    required this.id,
    required this.interestRequestId,
    required this.compradorId,
    required this.sellerId,
    required this.coffeeLotId,
    required this.cantidad,
    required this.unidad,
    this.comentario,
    this.lugarEntrega,
    this.estado = EstadoCotizacion.pendiente,
    DateTime? fecha,
  }) : fecha = fecha ?? DateTime.now();
}
