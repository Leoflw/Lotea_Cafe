import '../data/codec.dart';

/// Documento `chats/{connectionId}/messages/{messageId}`.
class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String texto;

  /// Nulo mientras el servidor aún no ha confirmado la hora (escritura local
  /// pendiente); se muestra como "enviando".
  final DateTime? timestamp;
  final bool pendiente;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.texto,
    this.timestamp,
    this.pendiente = false,
  });

  factory ChatMessage.fromMap(String chatId, String id, Map<String, dynamic> m, {bool pendiente = false}) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: readString(m['senderId']) ?? '',
      texto: readString(m['texto']) ?? '',
      timestamp: readDate(m['createdAt']),
      pendiente: pendiente,
    );
  }
}
