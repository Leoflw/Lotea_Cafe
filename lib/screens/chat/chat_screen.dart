import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/mock_store.dart';
import '../../models/chat_message.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';

/// Chat privado entre comprador y vendedor tras el match. Mensajes viven
/// en el MockStore (memoria); se reconstruye automáticamente al enviar.
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otroNombre;

  const ChatScreen({super.key, required this.chatId, required this.otroNombre});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _uuid = const Uuid();

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _enviar() {
    final texto = _textCtrl.text.trim();
    if (texto.isEmpty) return;
    final uid = context.read<SessionProvider>().usuario!.uid;
    _textCtrl.clear();

    context.read<MockStore>().enviarMensaje(
          ChatMessage(
            id: _uuid.v4(),
            chatId: widget.chatId,
            senderId: uid,
            texto: texto,
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final miUid = context.read<SessionProvider>().usuario!.uid;
    final mensajes = context.watch<MockStore>().mensajesDeChat(widget.chatId);

    return Scaffold(
      appBar: AppBar(title: Text(widget.otroNombre)),
      body: Column(
        children: [
          Expanded(
            child: mensajes.isEmpty
                ? Center(
                    child: Text(
                      'Aún no hay mensajes.\n¡Saluda y empieza a negociar tu compra!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: mensajes.length,
                    itemBuilder: (context, i) {
                      final m = mensajes[i];
                      final esMio = m.senderId == miUid;
                      return _Burbuja(mensaje: m, esMio: esMio);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviar(),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.coffeeMedium,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _enviar,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  final ChatMessage mensaje;
  final bool esMio;

  const _Burbuja({required this.mensaje, required this.esMio});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: esMio ? AppColors.coffeeMedium : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(esMio ? 16 : 2),
            bottomRight: Radius.circular(esMio ? 2 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              mensaje.texto,
              style: TextStyle(color: esMio ? Colors.white : AppColors.coffeeDark),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat.Hm().format(mensaje.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: esMio ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
