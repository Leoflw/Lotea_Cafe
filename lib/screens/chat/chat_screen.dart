import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/mock_store.dart';
import '../../models/chat_message.dart';
import '../../models/coffee_lot.dart';
import '../../models/interest_request.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import 'quote_request_screen.dart';

/// Chat comercial dentro de una conexión ya aceptada. Cabecera con
/// contexto (vendedor, café, precio) y acciones explícitas [Ver café] /
/// [Solicitar cotización] — sección 19, 2ª ronda. No implementa pagos.
class ChatScreen extends StatefulWidget {
  final String interestRequestId;
  final String otroNombre;

  const ChatScreen({super.key, required this.interestRequestId, required this.otroNombre});

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
          ChatMessage(id: _uuid.v4(), chatId: widget.interestRequestId, senderId: uid, texto: texto),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final miUid = context.read<SessionProvider>().usuario!.uid;
    final conexion = store.solicitudPorId(widget.interestRequestId);
    final lote = conexion != null ? store.lotePorId(conexion.coffeeLotId) : null;
    final mensajes = store.mensajesDeChat(widget.interestRequestId);

    return Scaffold(
      appBar: AppBar(title: Text(widget.otroNombre)),
      body: Column(
        children: [
          if (lote != null) _EncabezadoComercial(lote: lote, conexion: conexion!),
          Expanded(
            child: mensajes.isEmpty
                ? Center(
                    child: Text(
                      'Conexión comercial establecida.\n¡Saluda y empieza a negociar!',
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
                      return _Burbuja(mensaje: m, esMio: m.senderId == miUid);
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.coffeeMedium,
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _enviar),
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

class _EncabezadoComercial extends StatelessWidget {
  final CoffeeLot lote;
  final InterestRequest conexion;
  const _EncabezadoComercial({required this.lote, required this.conexion});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.coffeeLight.withOpacity(0.35),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              AppImage(
                path: lote.fotos.isEmpty ? null : lote.fotos.first,
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(10),
                ampliable: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lote.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text(formatCOPPorUnidad(lote.precioCOP, lote.unidad), style: const TextStyle(fontSize: 12, color: AppColors.coffeeDark)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: lote.id))),
                  icon: const Icon(Icons.coffee_outlined, size: 16),
                  label: const Text('Ver café', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(36)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: conexion))),
                  icon: const Icon(Icons.request_quote_outlined, size: 16),
                  label: const Text('Cotizar', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(36)),
                ),
              ),
            ],
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
            Text(mensaje.texto, style: TextStyle(color: esMio ? Colors.white : AppColors.coffeeDark)),
            const SizedBox(height: 2),
            Text(DateFormat.Hm().format(mensaje.timestamp), style: TextStyle(fontSize: 10, color: esMio ? Colors.white70 : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
