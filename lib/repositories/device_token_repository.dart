import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/device_token_service.dart';
import 'repo_exception.dart';

/// Tokens FCM de los dispositivos de una persona:
/// `users/{uid}/deviceTokens/{tokenId}` con SOLO `token`, `plataforma` y `updatedAt`
/// (las reglas de Firestore rechazan cualquier otro campo y cualquier acceso a
/// los tokens de otra persona).
class DeviceTokenRepository implements DeviceTokenStore {
  final FirebaseFirestore _db;
  DeviceTokenRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid, String tokenId) =>
      _db.collection('users').doc(uid).collection('deviceTokens').doc(tokenId);

  @override
  Future<void> guardar({required String uid, required String tokenId, required String token, required String plataforma}) =>
      guardarEnFirestore(() => _ref(uid, tokenId).set({
            'token': token,
            'plataforma': plataforma,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  @override
  Future<void> eliminar({required String uid, required String tokenId}) =>
      guardarEnFirestore(() => _ref(uid, tokenId).delete());
}

/// Alias local de [guardar] (traduce excepciones de Firebase a [RepoException]).
Future<T> guardarEnFirestore<T>(Future<T> Function() accion) => guardar(accion);
