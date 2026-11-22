import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../utils/account_block.dart';
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
import '../../utils/negociacion_restringida.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/avatar_circular.dart';
import '../../widgets/cafe_no_disponible_view.dart';
import '../../widgets/modo_consulta_banner.dart';
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
  // Se activa cuando el servidor rechaza un mensaje por permisos: la conversación pasa a modo de
  // consulta (historial visible, sin campo de escritura). «Volver a intentar» lo desactiva.
  bool _soloConsulta = false;
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
  // «Cuenta eliminada» cuando la conexión marca a la otra parte como eliminada (título reactivo).
  String? _nombreContraparteEliminada;

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
    if (avisarSiCuentaBloqueada(context)) return;
    final uid = context.read<SessionProvider>().usuario?.uid;
    if (uid == null) return;
    // La otra persona eliminó su cuenta: el chat es solo historial (no se intenta enviar nada).
    if (_ultimaConexion?.nombreSiContraparteEliminada(uid) != null) return;
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
      if (!mounted) return;
      if (esRechazoPorPermisos(e)) {
        // Rechazo de las reglas: no hay mensaje enviado ni falso éxito; el historial no se toca y el borrador
        // se conserva en el controlador. El aviso persistente de modo de consulta (con «Volver a intentar»)
        // ya lo explica: no se muestra un SnackBar porque quedaría sobre ese botón. Si había uno de un error
        // anterior en pantalla, se retira por la misma razón.
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _soloConsulta = true);
      } else {
        mostrarError(context, e);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final miUid = context.read<SessionProvider>().usuario?.uid;
    final conexiones = context.read<InterestRequestRepository>();
    final chats = context.read<ChatRepository>();
    final nombre = _nombreContraparteEliminada ?? (widget.otroNombre.isEmpty ? 'Chat' : widget.otroNombre);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => liberarFoco(),
      child: DismissKeyboard(
        child: Scaffold(
          appBar: AppBar(
            centerTitle: false,
            titleSpacing: 0,
            title: Row(
              children: [
                AvatarCircular(fotoUrl: null, nombre: nombre, radius: 18, fontSize: 15, fontWeight: FontWeight.bold),
                const SizedBox(width: 10),
                Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
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
              // Depende SOLO del marcador de la OTRA persona (no del propio usuario ni de un rechazo de Firestore).
              final contraparteEliminada = conexion.nombreSiContraparteEliminada(miUid) != null;
              _ultimaConexion = conexion;
              final eliminada = conexion.nombreSiContraparteEliminada(miUid);
              if (eliminada != null && eliminada != _nombreContraparteEliminada) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _nombreContraparteEliminada = eliminada);
                });
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => _marcarLeidoSiHaceFalta(conexion));
              return Column(
                children: [
                  _Encabezado(conexion: conexion, soyComprador: soyComprador, soloConsulta: _soloConsulta || contraparteEliminada),
                  Expanded(
                    child: StreamView<List<ChatMessage>>(
                      crear: () => chats.observar(widget.interestRequestId),
                      builder: (context, mensajes) {
                        if (mensajes.isEmpty) {
                          return const EmptyState(
                            icono: Icons.chat_bubble_outline,
                            titulo: 'Conexión comercial establecida',
                            subtitulo: '¡Saluda y empieza a negociar!',
                          );
                        }
                        // El stream trae del más antiguo al más reciente. Se
                        // intercala un separador cada vez que cambia el día y se
                        // muestra con reverse para quedar anclado abajo.
                        final items = _conSeparadores(mensajes).reversed.toList();
                        return ListView.builder(
                          reverse: true,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            if (item is DateTime) return _SeparadorDia(dia: item);
                            final m = item as ChatMessage;
                            return _Burbuja(mensaje: m, esMio: m.senderId == miUid);
                          },
                        );
                      },
                    ),
                  ),
                  if (contraparteEliminada) ...[
                    // Permanente: sin «Volver a intentar». El campo sigue visible pero deshabilitado, así el
                    // borrador que hubiera no se pierde en silencio.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: ModoConsultaBanner(
                        key: const ValueKey('chat_cuenta_eliminada'),
                        texto: mensajeChatContraparteEliminada,
                      ),
                    ),
                    _BarraEscritura(controller: _textCtrl, enviando: _enviando, onEnviar: _enviar, bloqueada: true),
                  ] else if (_soloConsulta)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: ModoConsultaBanner(
                          key: const ValueKey('chat_modo_consulta'),
                          texto: mensajeChatSoloConsulta,
                          botonReintentarKey: const ValueKey('chat_volver_a_intentar'),
                          onReintentar: () => setState(() => _soloConsulta = false),
                        ),
                      ),
                    )
                  else
                    _BarraEscritura(
                      controller: _textCtrl,
                      enviando: _enviando,
                      onEnviar: _enviar,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Mensajes (del más antiguo al más reciente) con un [DateTime] (solo el día)
  /// antes del primer mensaje de cada jornada. Un mensaje aún sin hora del
  /// servidor se agrupa con «hoy».
  List<Object> _conSeparadores(List<ChatMessage> mensajes) {
    final salida = <Object>[];
    DateTime? ultimoDia;
    for (final m in mensajes) {
      final t = m.timestamp ?? DateTime.now();
      final dia = DateTime(t.year, t.month, t.day);
      if (ultimoDia == null || dia != ultimoDia) {
        salida.add(dia);
        ultimoDia = dia;
      }
      salida.add(m);
    }
    return salida;
  }
}

/// Campo de escritura y botón de envío. El botón se ve atenuado mientras no
/// haya texto, pero conserva su comportamiento de siempre (`_enviar` ya ignora
/// los mensajes vacíos). Con teclado de una línea y envío desde el teclado.
class _BarraEscritura extends StatelessWidget {
  final TextEditingController controller;
  final bool enviando;
  final VoidCallback onEnviar;
  /// Chat solo de consulta permanente: campo y botón de envío deshabilitados (el texto se conserva).
  final bool bloqueada;
  const _BarraEscritura({required this.controller, required this.enviando, required this.onEnviar, this.bloqueada = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !enviando && !bloqueada,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: ChatRepository.maxCaracteres,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  onSubmitted: bloqueada ? null : (_) => onEnviar(),
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.coffeeMedium, width: 1.4)),
                    filled: true,
                    fillColor: AppColors.surfaceWarm,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final hayTexto = controller.text.trim().isNotEmpty;
                  return Material(
                    color: hayTexto || enviando ? AppColors.coffeeMedium : AppColors.coffeeLight,
                    shape: const CircleBorder(),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: enviando
                          ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                          : IconButton(
                              tooltip: 'Enviar',
                              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                              onPressed: bloqueada ? null : onEnviar,
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final InterestRequest conexion;
  final bool soyComprador;
  // En modo de consulta «Cotizar» (iniciar una operación comercial) queda deshabilitado; «Ver café» sigue.
  final bool soloConsulta;
  const _Encabezado({required this.conexion, required this.soyComprador, this.soloConsulta = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          AppImage(path: conexion.loteFoto, width: 40, height: 40, borderRadius: BorderRadius.circular(AppRadius.control - 2), ampliable: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Café', style: Theme.of(context).textTheme.labelSmall),
                Text(conexion.loteNombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.coffeeDark)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: conexion.coffeeLotId, respaldo: LoteRespaldo.desdeConexion(conexion)))),
            style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('Ver café'),
          ),
          if (soyComprador)
            TextButton(
              onPressed: soloConsulta ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: conexion))),
              style: TextButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text('Cotizar'),
            ),
        ],
      ),
    );
  }
}

/// Separador con el día («Hoy», «Ayer» o la fecha).
class _SeparadorDia extends StatelessWidget {
  final DateTime dia;
  const _SeparadorDia({required this.dia});

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final diferencia = hoyDia.difference(dia).inDays;
    final texto = diferencia == 0 ? 'Hoy' : (diferencia == 1 ? 'Ayer' : formatFecha(dia));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(texto, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
        ),
      ),
    );
  }
}

/// Burbuja de mensaje: suave y legible. Los míos en tono arena (texto café
/// oscuro, sin colores intensos), los del otro en blanco con borde fino; la
/// esquina del lado de quien escribe es más cerrada.
class _Burbuja extends StatelessWidget {
  final ChatMessage mensaje;
  final bool esMio;
  const _Burbuja({required this.mensaje, required this.esMio});

  @override
  Widget build(BuildContext context) {
    final hora = mensaje.timestamp == null ? 'Enviando…' : DateFormat('HH:mm').format(mensaje.timestamp!);
    const radio = Radius.circular(16);
    const cerrado = Radius.circular(4);
    return Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: esMio ? AppColors.coffeeLight.withValues(alpha: 0.55) : AppColors.surface,
          border: esMio ? null : Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.only(
            topLeft: radio,
            topRight: radio,
            bottomLeft: esMio ? radio : cerrado,
            bottomRight: esMio ? cerrado : radio,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(mensaje.texto, style: const TextStyle(color: AppColors.coffeeDark, fontSize: 14.5, height: 1.35)),
            const SizedBox(height: 2),
            Text(hora, style: const TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}
