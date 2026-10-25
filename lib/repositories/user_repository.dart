import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import 'repo_exception.dart';

/// Colección `users/{uid}`.
class UserRepository {
  final FirebaseFirestore _db;
  UserRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db.collection('users').doc(uid);

  /// Emite `null` si el documento no existe (cuenta de Authentication sin
  /// perfil todavía). Los errores se propagan como [RepoException].
  Stream<AppUser?> observar(String uid) {
    return traducirErrores(_ref(uid).snapshots().map((snap) {
      final data = snap.data();
      return data == null ? null : AppUser.fromMap(snap.id, data);
    }));
  }

  Future<AppUser?> obtener(String uid) => guardar(() async {
        final snap = await _ref(uid).get();
        final data = snap.data();
        return data == null ? null : AppUser.fromMap(snap.id, data);
      });

  /// Crea el documento del usuario justo después del registro. Las reglas
  /// exigen que el id sea el UID autenticado.
  Future<void> crear(AppUser usuario) => guardar(() async {
        await _ref(usuario.uid).set({
          'uid': usuario.uid,
          'email': usuario.email,
          'rol': usuario.rol.name,
          ...usuario.toEditableMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Actualiza solo los campos editables; el rol, el correo y el UID no se
  /// envían (y las reglas rechazarían un cambio).
  Future<void> actualizar(AppUser usuario) => guardar(() async {
        await _ref(usuario.uid).update({
          ...usuario.toEditableMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
}
