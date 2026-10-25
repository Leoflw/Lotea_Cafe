import '../data/codec.dart';

enum TipoFavorito { cafe, vendedor }

/// Documento `users/{uid}/favorites/{tipo}_{refId}`. El id determinista evita
/// duplicados. Se mantiene separado de las solicitudes: guardar no implica
/// interés comercial.
class Favorite {
  final String id;
  final String compradorId;
  final TipoFavorito tipo;
  final String refId; // coffeeLotId o sellerId según [tipo]
  final DateTime? fecha;

  const Favorite({
    required this.id,
    required this.compradorId,
    required this.tipo,
    required this.refId,
    this.fecha,
  });

  static String idPara(TipoFavorito tipo, String refId) => '${tipo.name}_$refId';

  Map<String, dynamic> toCreateMap() => {'tipo': tipo.name, 'refId': refId};

  factory Favorite.fromMap(String compradorId, String id, Map<String, dynamic> m) {
    return Favorite(
      id: id,
      compradorId: compradorId,
      tipo: readEnum(TipoFavorito.values, m['tipo'], TipoFavorito.cafe),
      refId: readString(m['refId']) ?? '',
      fecha: readDate(m['createdAt']),
    );
  }
}
