import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import 'repo_exception.dart';

/// Mensajes en `chats/{connectionId}/messages/{messageId}`. El chat solo
/// existe para conexiones comerciales ACEPTADAS (las reglas lo verifican).
class ChatRepository {
  static const maxCaracteres = 2000;
  static const limiteMensajes = 100;

  final FirebaseFirestore _db;
  ChatRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String chatId) =>
      _db.collection('chats').doc(chatId).collection('messages');

  /// Últimos [limiteMensajes] mensajes, del más antiguo al más reciente.
  /// Incluye los pendientes de confirmar (`pendiente == true`).
  Stream<List<ChatMessage>> observar(String chatId) {
    final s = _col(chatId)
        .orderBy('createdAt', descending: true)
        .limit(limiteMensajes)
        .snapshots(includeMetadataChanges: true)
        .map((q) => q.docs
            .map((d) => ChatMessage.fromMap(chatId, d.id, d.data(), pendiente: d.metadata.hasPendingWrites))
            .toList()
            .reversed
            .toList());
    return traducirErrores(s);
  }

  /// Envía un mensaje. [mensajeId] lo genera el cliente: si el envío se
  /// reintenta con el mismo id no se duplica. Completa cuando el SERVIDOR
  /// confirma (no antes), así un rechazo de las reglas llega como error.
  Future<void> enviar({
    required String chatId,
    required String mensajeId,
    required String senderId,
    required String texto,
  }) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      throw const RepoException(RepoErrorKind.validacion, 'Escribe un mensaje.');
    }
    if (limpio.length > maxCaracteres) {
      throw const RepoException(RepoErrorKind.validacion, 'El mensaje es demasiado largo (máximo $maxCaracteres caracteres).');
    }
    await guardar(() => _col(chatId).doc(mensajeId).set({
          'senderId': senderId,
          'texto': limpio,
          'createdAt': FieldValue.serverTimestamp(),
        }));
  }
}
