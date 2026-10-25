class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String texto;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.texto,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
