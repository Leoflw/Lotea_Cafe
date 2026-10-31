import '../data/codec.dart';

/// Ciclo de vida de una cotización. Cada estado dice QUIÉN actuó: no existe
/// un estado ambiguo como "aceptada" sin indicar si fue la oferta o la
/// solicitud, ni quién la aceptó.
enum EstadoCotizacion {
  /// El comprador pidió precio y espera respuesta del vendedor.
  solicitudPendiente,

  /// El vendedor envió una oferta concreta y espera al comprador.
  ofertaEnviada,

  /// El comprador pidió un ajuste; el vendedor debe revisar y reenviar.
  revisionSolicitada,

  /// El comprador aceptó la oferta. NO crea pedido ni pago.
  ofertaAceptada,

  /// El comprador rechazó la oferta.
  ofertaRechazada,

  /// El vendedor rechazó la solicitud (sin oferta).
  solicitudRechazada,

  /// El comprador canceló antes de cerrar la negociación.
  cancelada,

  /// Estado derivado: la oferta superó su vigencia sin respuesta. Se calcula
  /// al leer ([QuoteRequest.estadoEfectivo]); no se escribe en Firestore.
  ofertaVencida,
}

extension EstadoCotizacionX on EstadoCotizacion {
  String get label {
    switch (this) {
      case EstadoCotizacion.solicitudPendiente:
        return 'Esperando respuesta del vendedor';
      case EstadoCotizacion.ofertaEnviada:
        return 'Oferta enviada';
      case EstadoCotizacion.revisionSolicitada:
        return 'Revisión solicitada';
      case EstadoCotizacion.ofertaAceptada:
        return 'Oferta aceptada';
      case EstadoCotizacion.ofertaRechazada:
        return 'Oferta rechazada';
      case EstadoCotizacion.solicitudRechazada:
        return 'Solicitud rechazada por el vendedor';
      case EstadoCotizacion.cancelada:
        return 'Cancelada';
      case EstadoCotizacion.ofertaVencida:
        return 'Oferta vencida';
    }
  }

  /// Etiqueta corta para chips.
  String get corto {
    switch (this) {
      case EstadoCotizacion.solicitudPendiente:
        return 'Pendiente';
      case EstadoCotizacion.ofertaEnviada:
        return 'Oferta enviada';
      case EstadoCotizacion.revisionSolicitada:
        return 'En revisión';
      case EstadoCotizacion.ofertaAceptada:
        return 'Aceptada';
      case EstadoCotizacion.ofertaRechazada:
        return 'Rechazada';
      case EstadoCotizacion.solicitudRechazada:
        return 'Rechazada por vendedor';
      case EstadoCotizacion.cancelada:
        return 'Cancelada';
      case EstadoCotizacion.ofertaVencida:
        return 'Vencida';
    }
  }
}

enum ActorCotizacion { comprador, vendedor }

/// Única fuente de verdad de las transiciones permitidas en el cliente. Las
/// reglas de Firestore (`firestore.rules`) aplican la MISMA tabla en el
/// servidor; si cambias una, cambia la otra.
class QuoteStateMachine {
  static const Map<EstadoCotizacion, Map<ActorCotizacion, Set<EstadoCotizacion>>> _tabla = {
    EstadoCotizacion.solicitudPendiente: {
      ActorCotizacion.vendedor: {EstadoCotizacion.ofertaEnviada, EstadoCotizacion.solicitudRechazada},
      ActorCotizacion.comprador: {EstadoCotizacion.cancelada},
    },
    EstadoCotizacion.ofertaEnviada: {
      ActorCotizacion.comprador: {
        EstadoCotizacion.ofertaAceptada,
        EstadoCotizacion.ofertaRechazada,
        EstadoCotizacion.revisionSolicitada,
        EstadoCotizacion.cancelada,
      },
    },
    EstadoCotizacion.revisionSolicitada: {
      ActorCotizacion.vendedor: {EstadoCotizacion.ofertaEnviada, EstadoCotizacion.solicitudRechazada},
      ActorCotizacion.comprador: {EstadoCotizacion.cancelada},
    },
  };

  static Set<EstadoCotizacion> destinos(EstadoCotizacion desde, ActorCotizacion actor) =>
      _tabla[desde]?[actor] ?? const <EstadoCotizacion>{};

  static bool puede(EstadoCotizacion desde, EstadoCotizacion hacia, ActorCotizacion actor) =>
      destinos(desde, actor).contains(hacia);

  static bool esTerminal(EstadoCotizacion e) => !_tabla.containsKey(e);

  /// Estados en los que el vendedor tiene una acción pendiente.
  static bool requiereRespuestaDelVendedor(EstadoCotizacion e) =>
      e == EstadoCotizacion.solicitudPendiente || e == EstadoCotizacion.revisionSolicitada;
}

class QuoteTotals {
  final int subtotalCOP;
  final int envioCOP;
  final int totalCOP;
  const QuoteTotals(this.subtotalCOP, this.envioCOP, this.totalCOP);
}

/// Cálculo centralizado de importes en pesos enteros (COP no usa decimales).
/// Se usa en el formulario de oferta Y antes de guardar; las reglas de
/// Firestore vuelven a comprobar que `subtotal = cantidad × precio` (±0,5) y
/// `total = subtotal + envío`.
class QuoteCalculator {
  static QuoteTotals calcular({
    required double cantidad,
    required int precioUnitarioCOP,
    int envioCOP = 0,
  }) {
    final subtotal = (cantidad * precioUnitarioCOP).round();
    return QuoteTotals(subtotal, envioCOP, subtotal + envioCOP);
  }
}

class QuoteLimits {
  static const maxCantidad = 1000000.0;
  static const maxLugar = 120;
  static const maxComentario = 500;
  static const maxCondiciones = 800;
  static const maxMensaje = 500;
  static const maxTiempoEntrega = 80;
  static const maxPrecioUnitario = 100000000;
  static const maxEnvio = 100000000;
  static const unidadesPermitidas = ['kg', 'lb', 'saco (70kg)'];
}

/// Validaciones compartidas por los formularios y los repositorios.
class QuoteValidator {
  static String? solicitud({
    required double? cantidad,
    required String unidad,
    String? lugarEntrega,
    String? comentario,
  }) {
    if (cantidad == null || cantidad <= 0) return 'Indica una cantidad mayor que cero.';
    if (cantidad > QuoteLimits.maxCantidad) return 'La cantidad es demasiado grande.';
    if (!QuoteLimits.unidadesPermitidas.contains(unidad)) return 'Unidad no permitida.';
    if ((lugarEntrega ?? '').length > QuoteLimits.maxLugar) {
      return 'El lugar de entrega admite hasta ${QuoteLimits.maxLugar} caracteres.';
    }
    if ((comentario ?? '').length > QuoteLimits.maxComentario) {
      return 'El comentario admite hasta ${QuoteLimits.maxComentario} caracteres.';
    }
    return null;
  }

  static String? oferta({
    required int? precioUnitarioCOP,
    required int? envioCOP,
    required String tiempoEntrega,
    String? condiciones,
    String? mensaje,
    DateTime? vigenciaHasta,
    DateTime? ahora,
  }) {
    if (precioUnitarioCOP == null || precioUnitarioCOP <= 0) return 'Indica un precio unitario mayor que cero.';
    if (precioUnitarioCOP > QuoteLimits.maxPrecioUnitario) return 'El precio unitario es demasiado alto.';
    if (envioCOP == null || envioCOP < 0) return 'El costo de envío no puede ser negativo.';
    if (envioCOP > QuoteLimits.maxEnvio) return 'El costo de envío es demasiado alto.';
    if (tiempoEntrega.trim().isEmpty) return 'Indica el tiempo estimado de entrega.';
    if (tiempoEntrega.length > QuoteLimits.maxTiempoEntrega) {
      return 'El tiempo de entrega admite hasta ${QuoteLimits.maxTiempoEntrega} caracteres.';
    }
    if ((condiciones ?? '').length > QuoteLimits.maxCondiciones) {
      return 'Las condiciones admiten hasta ${QuoteLimits.maxCondiciones} caracteres.';
    }
    if ((mensaje ?? '').length > QuoteLimits.maxMensaje) {
      return 'El mensaje admite hasta ${QuoteLimits.maxMensaje} caracteres.';
    }
    if (vigenciaHasta != null && !vigenciaHasta.isAfter(ahora ?? DateTime.now())) {
      return 'La vigencia debe ser una fecha futura.';
    }
    return null;
  }
}

/// Oferta concreta del vendedor. Los importes son enteros en COP.
class QuoteOffer {
  final int precioUnitarioCOP;
  final String unidadPrecio;
  final int subtotalCOP;
  final int envioCOP;
  final int totalCOP;
  final String tiempoEntrega;
  final DateTime? vigenciaHasta;
  final String condiciones;
  final String? mensaje;

  /// 1 para la primera oferta; aumenta con cada nueva propuesta tras una
  /// solicitud de revisión.
  final int version;

  const QuoteOffer({
    required this.precioUnitarioCOP,
    required this.unidadPrecio,
    required this.subtotalCOP,
    required this.envioCOP,
    required this.totalCOP,
    required this.tiempoEntrega,
    this.vigenciaHasta,
    this.condiciones = '',
    this.mensaje,
    this.version = 1,
  });

  bool estaVencida([DateTime? ahora]) =>
      vigenciaHasta != null && !vigenciaHasta!.isAfter(ahora ?? DateTime.now());

  Map<String, dynamic> toMap() => {
        'precioUnitarioCOP': precioUnitarioCOP,
        'unidadPrecio': unidadPrecio,
        'subtotalCOP': subtotalCOP,
        'envioCOP': envioCOP,
        'totalCOP': totalCOP,
        'tiempoEntrega': tiempoEntrega,
        'vigenciaHasta': vigenciaHasta,
        'condiciones': condiciones,
        'mensaje': mensaje,
        'version': version,
      };

  static QuoteOffer? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final precio = readInt(m['precioUnitarioCOP']);
    final total = readInt(m['totalCOP']);
    if (precio == null || total == null) return null;
    return QuoteOffer(
      precioUnitarioCOP: precio,
      unidadPrecio: readString(m['unidadPrecio']) ?? 'kg',
      subtotalCOP: readInt(m['subtotalCOP']) ?? total,
      envioCOP: readInt(m['envioCOP']) ?? 0,
      totalCOP: total,
      tiempoEntrega: readString(m['tiempoEntrega']) ?? '',
      vigenciaHasta: readDate(m['vigenciaHasta']),
      condiciones: readString(m['condiciones']) ?? '',
      mensaje: readString(m['mensaje']),
      version: readInt(m['version']) ?? 1,
    );
  }
}

enum EventoCotizacion {
  solicitudCreada,
  ofertaEnviada,
  revisionSolicitada,
  ofertaAceptada,
  ofertaRechazada,
  solicitudRechazada,
  cancelada,
}

extension EventoCotizacionX on EventoCotizacion {
  String get label {
    switch (this) {
      case EventoCotizacion.solicitudCreada:
        return 'Solicitud creada';
      case EventoCotizacion.ofertaEnviada:
        return 'Oferta enviada';
      case EventoCotizacion.revisionSolicitada:
        return 'Ajuste solicitado';
      case EventoCotizacion.ofertaAceptada:
        return 'Oferta aceptada';
      case EventoCotizacion.ofertaRechazada:
        return 'Oferta rechazada';
      case EventoCotizacion.solicitudRechazada:
        return 'Solicitud rechazada';
      case EventoCotizacion.cancelada:
        return 'Cotización cancelada';
    }
  }
}

/// Entrada del historial: `quotes/{id}/events/{eventId}`. Solo se crean, no
/// se editan ni se borran.
class QuoteEvent {
  final String id;
  final EventoCotizacion tipo;
  final ActorCotizacion actor;
  final String actorId;
  final DateTime? fecha;
  final String? nota;
  final int? totalCOP;
  final int? versionOferta;

  const QuoteEvent({
    required this.id,
    required this.tipo,
    required this.actor,
    required this.actorId,
    this.fecha,
    this.nota,
    this.totalCOP,
    this.versionOferta,
  });

  factory QuoteEvent.fromMap(String id, Map<String, dynamic> m) {
    return QuoteEvent(
      id: id,
      tipo: readEnum(EventoCotizacion.values, m['tipo'], EventoCotizacion.solicitudCreada),
      actor: readEnum(ActorCotizacion.values, m['actor'], ActorCotizacion.comprador),
      actorId: readString(m['actorId']) ?? '',
      fecha: readDate(m['fecha']),
      nota: readString(m['nota']),
      totalCOP: readInt(m['totalCOP']),
      versionOferta: readInt(m['versionOferta']),
    );
  }
}

/// Documento `quotes/{quoteId}`: la solicitud del comprador y la respuesta
/// del vendedor viven en el mismo documento.
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
  final QuoteOffer? oferta;
  final String? revisionComentario;
  final DateTime? fecha;
  final DateTime? updatedAt;

  // Copias de visualización (ver InterestRequest).
  final String compradorNombre;
  final String sellerNombre;
  final String loteNombre;
  final String? loteFoto;

  const QuoteRequest({
    required this.id,
    required this.interestRequestId,
    required this.compradorId,
    required this.sellerId,
    required this.coffeeLotId,
    required this.cantidad,
    required this.unidad,
    this.comentario,
    this.lugarEntrega,
    this.estado = EstadoCotizacion.solicitudPendiente,
    this.oferta,
    this.revisionComentario,
    this.fecha,
    this.updatedAt,
    this.compradorNombre = '',
    this.sellerNombre = '',
    this.loteNombre = '',
    this.loteFoto,
  });

  /// Estado que se muestra: una oferta enviada cuya vigencia ya pasó se ve
  /// como vencida aunque en Firestore siga como `ofertaEnviada`.
  EstadoCotizacion estadoEfectivo([DateTime? ahora]) {
    if (estado == EstadoCotizacion.ofertaEnviada && (oferta?.estaVencida(ahora) ?? false)) {
      return EstadoCotizacion.ofertaVencida;
    }
    return estado;
  }

  bool get tieneOferta => oferta != null;

  Map<String, dynamic> toCreateMap() => {
        'interestRequestId': interestRequestId,
        'compradorId': compradorId,
        'sellerId': sellerId,
        'coffeeLotId': coffeeLotId,
        'cantidad': cantidad,
        'unidad': unidad,
        'comentario': comentario,
        'lugarEntrega': lugarEntrega,
        'estado': EstadoCotizacion.solicitudPendiente.name,
        'oferta': null,
        'revisionComentario': null,
        'compradorNombre': compradorNombre,
        'sellerNombre': sellerNombre,
        'loteNombre': loteNombre,
        'loteFoto': loteFoto,
      };

  factory QuoteRequest.fromMap(String id, Map<String, dynamic> m) {
    return QuoteRequest(
      id: id,
      interestRequestId: readString(m['interestRequestId']) ?? '',
      compradorId: readString(m['compradorId']) ?? '',
      sellerId: readString(m['sellerId']) ?? '',
      coffeeLotId: readString(m['coffeeLotId']) ?? '',
      cantidad: readDouble(m['cantidad']) ?? 0,
      unidad: readString(m['unidad']) ?? 'kg',
      comentario: readString(m['comentario']),
      lugarEntrega: readString(m['lugarEntrega']),
      estado: readEnum(EstadoCotizacion.values, m['estado'], EstadoCotizacion.solicitudPendiente),
      oferta: QuoteOffer.fromMap(m['oferta']),
      revisionComentario: readString(m['revisionComentario']),
      fecha: readDate(m['createdAt']),
      updatedAt: readDate(m['updatedAt']),
      compradorNombre: readString(m['compradorNombre']) ?? '',
      sellerNombre: readString(m['sellerNombre']) ?? '',
      loteNombre: readString(m['loteNombre']) ?? '',
      loteFoto: readString(m['loteFoto']),
    );
  }
}
