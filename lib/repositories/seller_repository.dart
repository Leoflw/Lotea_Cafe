import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/seller_profile.dart';
import '../utils/photo_limits.dart';
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
        final previo = await ref.get();
        final existe = previo.exists;
        // Límite de la galería (PhotoLimits.maxGaleriaMarca); la foto principal
        // no cuenta. Un perfil antiguo con más fotos puede guardarse con las
        // mismas o menos, pero no con más.
        final galeriaPrevia = previo.data()?['galeria'];
        final excesoGaleria = PhotoLimits.validarCantidad(
          nuevo: perfil.galeria.length,
          max: PhotoLimits.maxGaleriaMarca,
          previo: galeriaPrevia is List ? galeriaPrevia.length : 0,
          galeria: true,
        );
        if (excesoGaleria != null) throw RepoException(RepoErrorKind.validacion, excesoGaleria);
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
