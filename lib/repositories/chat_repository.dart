import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import '../services/push_notifier.dart';
import 'repo_exception.dart';

/// Mensajes en `chats/{connectionId}/messages/{messageId}`. El chat solo
/// existe para conexiones comerciales ACEPTADAS (las reglas lo verifican).
class ChatRepository {
  static const maxCaracteres = 2000;
  static const limiteMensajes = 100;

  final FirebaseFirestore _db;
  final NotificadorPush? _notificador;
  ChatRepository({FirebaseFirestore? db, NotificadorPush? notificador})
      : _db = db ?? FirebaseFirestore.instance,
        _notificador = notificador;

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
    // Un solo lote atómico: el mensaje y el «último mensaje» de la conexión
    // (lo que activa el indicador de no leído de la otra persona). Si uno falla,
    // ninguno se guarda, y un reintento con el mismo id no duplica nada.
    final lote = _db.batch();
    lote.set(_col(chatId).doc(mensajeId), {
      'senderId': senderId,
      'texto': limpio,
      'createdAt': FieldValue.serverTimestamp(),
    });
    lote.update(_db.collection('interestRequests').doc(chatId), {
      'ultimoMensajeAt': FieldValue.serverTimestamp(),
      'ultimoMensajeDe': senderId,
      // Vincula la actualización al mensaje creado en este mismo lote: las
      // reglas (getAfter) rechazan un «último mensaje» sin mensaje real.
      'ultimoMensajeId': mensajeId,
    });
    await guardar(() => lote.commit());
    // Solo llega aquí si el servidor CONFIRMÓ el lote. El aviso no se espera y su
    // error nunca hace fallar un mensaje que ya se guardó.
    final n = _notificador;
    if (n != null) avisarSinEsperar(() => n.mensajeEnviado(conexionId: chatId, mensajeId: mensajeId));
  }
}
