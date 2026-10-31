import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/chat_message.dart';
import '../../models/interest_request.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/interest_request_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../services/push_navigation.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/focus_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/dismiss_keyboard.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import '../quotes/quote_request_screen.dart';

/// Chat de una conexión comercial aceptada. Los mensajes viven en
/// `chats/{connectionId}/messages`; las reglas solo permiten escribir a los
/// dos participantes y solo si la conexión está aceptada.
class ChatScreen extends StatefulWidget {
  final String interestRequestId;
  final String otroNombre;
  const ChatScreen({super.key, required this.interestRequestId, required this.otroNombre});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _textCtrl = TextEditingController();
  final _uuid = const Uuid();
  late final PushCoordinator _push;
  bool _enviando = false;
  // Id del mensaje en curso: si el envío falla y se reintenta con el mismo
  // texto, se reutiliza el id y no se duplica.
  String? _idEnCurso;
  String? _textoEnCurso;

  // Lectura: los mensajes recibidos se marcan como leídos SOLO mientras el chat
  // está abierto y la app en primer plano (no si está en segundo plano).
  bool _primerPlano = true;
  bool _marcando = false;
  DateTime? _ultimoMensajeIntentado; // evita repetir la escritura si falla
  InterestRequest? _ultimaConexion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Con este chat a la vista no se muestra el aviso de «mensaje nuevo» en primer plano.
    _push = context.read<PushCoordinator>();
    _push.chatAbierto = widget.interestRequestId;
  }

  @override
  void dispose() {
    if (_push.chatAbierto == widget.interestRequestId) _push.chatAbierto = null;
    WidgetsBinding.instance.removeObserver(this);
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _primerPlano = state == AppLifecycleState.resumed;
    if (_primerPlano) {
      _ultimoMensajeIntentado = null; // al volver se permite reintentar
      final c = _ultimaConexion;
      if (c != null) _marcarLeidoSiHaceFalta(c);
    }
  }

  /// Marca la conversación como leída para esta persona si tiene mensajes
  /// recibidos sin leer. Solo toca su propio estado de lectura.
  Future<void> _marcarLeidoSiHaceFalta(InterestRequest conexion) async {
    if (!mounted || !_primerPlano || _marcando) return;
    final uid = context.read<SessionProvider>().usuario?.uid;
    if (uid == null || !conexion.tieneMensajesNoLeidos(uid)) return;
    if (_ultimoMensajeIntentado != null && conexion.ultimoMensajeAt == _ultimoMensajeIntentado) return;
    final repo = context.read<InterestRequestRepository>();
    _marcando = true;
    _ultimoMensajeIntentado = conexion.ultimoMensajeAt;
    try {
      await repo.marcarChatLeido(conexion.id, esComprador: uid == conexion.compradorId);
    } on RepoException {
      // Sin aviso: es una tarea de fondo. Se reintenta al volver a la app o al
      // llegar otro mensaje, y el indicador sigue visible hasta que se logre.
    } finally {
      _marcando = false;
    }
    // Si llegó otro mensaje mientras se escribía, se vuelve a evaluar.
    final ultima = _ultimaConexion;
    if (mounted && ultima != null) _marcarLeidoSiHaceFalta(ultima);
  }

  Future<void> _enviar() async {
    final texto = _textCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    final uid = context.read<SessionProvider>().usuario?.uid;
    if (uid == null) return;
    final repo = context.read<ChatRepository>();
    if (_textoEnCurso != texto) {
      _idEnCurso = _uuid.v4();
      _textoEnCurso = texto;
    }
    setState(() => _enviando = true);
    try {
      await repo.enviar(chatId: widget.interestRequestId, mensajeId: _idEnCurso!, senderId: uid, texto: texto);
      _textCtrl.clear();
      _idEnCurso = null;
      _textoEnCurso = null;
    } on RepoException catch (e) {
      // El texto se conserva en el campo para poder reintentar.
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final miUid = context.read<SessionProvider>().usuario?.uid;
    final conexiones = context.read<InterestRequestRepository>();
    final chats = context.read<ChatRepository>();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => liberarFoco(),
      child: DismissKeyboard(
        child: Scaffold(
          appBar: AppBar(title: Text(widget.otroNombre.isEmpty ? 'Chat' : widget.otroNombre)),
          body: StreamView<InterestRequest?>(
            crear: () => conexiones.observar(widget.interestRequestId),
            builder: (context, conexion) {
              if (conexion == null || !conexion.esConexion) {
                return const EmptyState(
                  icono: Icons.lock_outline,
                  titulo: 'Chat no disponible',
                  subtitulo: 'El chat se habilita cuando el vendedor acepta la solicitud.',
                );
              }
              final soyComprador = miUid == conexion.compradorId;
              _ultimaConexion = conexion;
              WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeidoSiHaceFalta(conexion));
              return Column(
                children: [
                  _Encabezado(conexion: conexion, soyComprador: soyComprador),
                  Expanded(
                    child: StreamView<List<ChatMessage>>(
                      crear: () => chats.observar(widget.interestRequestId),
                      builder: (context, mensajes) {
                        if (mensajes.isEmpty) {
                          return Center(
                            child: Text(
                              'Conexión comercial establecida.\n¡Saluda y empieza a negociar!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          );
                        }
                        // El stream trae del más antiguo al más reciente; se
                        // muestra con reverse para quedar anclado abajo.
                        final invertidos = mensajes.reversed.toList();
                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: invertidos.length,
                          itemBuilder: (context, i) => _Burbuja(mensaje: invertidos[i], esMio: invertidos[i].senderId == miUid),
                        );
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
                              enabled: !_enviando,
                              textInputAction: TextInputAction.send,
                              maxLength: ChatRepository.maxCaracteres,
                              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
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
                            radius: 24,
                            backgroundColor: AppColors.coffeeMedium,
                            child: _enviando
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : IconButton(
                                    tooltip: 'Enviar',
                                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                                    onPressed: _enviar,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final InterestRequest conexion;
  final bool soyComprador;
  const _Encabezado({required this.conexion, required this.soyComprador});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.coffeeLight.withOpacity(0.35),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          AppImage(path: conexion.loteFoto, width: 40, height: 40, borderRadius: BorderRadius.circular(10), ampliable: false),
          const SizedBox(width: 10),
          Expanded(
            child: Text(conexion.loteNombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: conexion.coffeeLotId))),
            child: const Text('Ver café'),
          ),
          if (soyComprador)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: conexion))),
              child: const Text('Cotizar'),
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
    final hora = mensaje.timestamp == null ? 'Enviando…' : DateFormat('HH:mm').format(mensaje.timestamp!);
    return Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: esMio ? AppColors.coffeeMedium : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(mensaje.texto, style: TextStyle(color: esMio ? Colors.white : Colors.black87)),
            const SizedBox(height: 3),
            Text(hora, style: TextStyle(fontSize: 10, color: esMio ? Colors.white70 : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
