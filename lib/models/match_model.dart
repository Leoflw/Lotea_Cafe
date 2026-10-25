enum MatchStatus { matched }

class MatchModel {
  final String id;
  final String compradorId;
  final String vendedorId;
  final String perfilId;
  final DateTime createdAt;

  MatchModel({
    required this.id,
    required this.compradorId,
    required this.vendedorId,
    required this.perfilId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Id determinístico de sala de chat por par comprador/vendedor+perfil.
  String get chatId => '${compradorId}_${vendedorId}_$perfilId';
}
