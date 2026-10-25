import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/favorite.dart';
import 'repo_exception.dart';

/// Subcolección `users/{uid}/favorites/{tipo}_{refId}`.
class FavoriteRepository {
  final FirebaseFirestore _db;
  FavoriteRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('favorites');

  Stream<List<Favorite>> observar(String compradorId) {
    final s = _col(compradorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((q) => q.docs.map((d) => Favorite.fromMap(compradorId, d.id, d.data())).toList());
    return traducirErrores(s);
  }

  /// Guarda o quita un favorito. Con id determinista no hay duplicados.
  Future<void> alternar({
    required String compradorId,
    required TipoFavorito tipo,
    required String refId,
    required bool yaEsFavorito,
  }) =>
      guardar(() async {
        final ref = _col(compradorId).doc(Favorite.idPara(tipo, refId));
        if (yaEsFavorito) {
          await ref.delete();
        } else {
          await ref.set({
            'tipo': tipo.name,
            'refId': refId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
}
