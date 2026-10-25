import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/seller_profile.dart';
import 'repo_exception.dart';

/// Colección `sellerProfiles/{uid}` (perfil público del vendedor).
class SellerRepository {
  final FirebaseFirestore _db;
  SellerRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db.collection('sellerProfiles').doc(uid);

  Stream<SellerProfile?> observar(String sellerId) {
    return traducirErrores(_ref(sellerId).snapshots().map((s) {
      final d = s.data();
      return d == null ? null : SellerProfile.fromMap(s.id, d);
    }));
  }

  Future<SellerProfile?> obtener(String sellerId) => guardar(() async {
        final s = await _ref(sellerId).get();
        final d = s.data();
        return d == null ? null : SellerProfile.fromMap(s.id, d);
      });

  /// Crea o actualiza el perfil del propietario. `verificado`,
  /// `calificacionPromedio` y `numOperaciones` nunca se envían desde la app.
  Future<void> guardarPerfil(SellerProfile perfil) => guardar(() async {
        final ref = _ref(perfil.id);
        final existe = (await ref.get()).exists;
        if (existe) {
          await ref.update({
            ...perfil.toEditableMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await ref.set({
            ...perfil.toEditableMap(),
            'verificado': false,
            'calificacionPromedio': 0,
            'numOperaciones': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
}
