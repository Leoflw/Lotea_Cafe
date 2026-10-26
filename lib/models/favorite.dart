enum TipoFavorito { cafe, vendedor }

/// Un café o vendedor guardado por un comprador para revisar después.
/// Se mantiene deliberadamente separado de [InterestRequest]: guardar no
/// implica haber mostrado interés comercial.
class Favorite {
  final String id;
  final String compradorId;
  final TipoFavorito tipo;
  final String refId; // coffeeLotId o sellerId según [tipo]
  final DateTime fecha;

  Favorite({
    required this.id,
    required this.compradorId,
    required this.tipo,
    required this.refId,
    DateTime? fecha,
  }) : fecha = fecha ?? DateTime.now();
}
