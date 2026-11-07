import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/interest_request.dart';
import '../../repositories/interest_request_repository.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/avatar_circular.dart';
import '../../widgets/connection_tile.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/price_text.dart';
import '../../widgets/remote_view.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/unread_badge.dart';
import '../chat/chat_screen.dart';
import '../quotes/quote_detail_screen.dart';
import '../quotes/quote_widgets.dart';

/// Vendedor: compradores interesados, conexiones y cotizaciones recibidas.
class ReceivedRequestsScreen extends StatefulWidget {
  const ReceivedRequestsScreen({super.key});

  @override
  State<ReceivedRequestsScreen> createState() => _ReceivedRequestsScreenState();
}

class _ReceivedRequestsScreenState extends State<ReceivedRequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ActivityProvider>();
    final pendientes = a.pendientes;
    final conexiones = a.conexiones;
    final cotizaciones = a.listaCotizaciones;
    final cotizacionPorResponder = cotizaciones.any((q) => cotizacionRequiereAccion(q, verComoVendedor: true));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.coffeeMedium,
          unselectedLabelColor: AppColors.inkMuted,
          indicatorColor: AppColors.coffeeMedium,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(
              child: IndicadorNoLeido(
                visible: pendientes.isNotEmpty,
                etiqueta: 'Solicitudes por responder',
                child: Text('Interesados (${pendientes.length})'),
              ),
            ),
            Tab(
              child: IndicadorNoLeido(
                visible: a.chatsConNoLeidos > 0,
                child: Text('Conexiones (${conexiones.length})'),
              ),
            ),
            Tab(
              child: IndicadorNoLeido(
                visible: cotizacionPorResponder,
                etiqueta: 'Cotizaciones por responder',
                child: Text('Cotizaciones (${cotizaciones.length})'),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          RemoteView<List<InterestRequest>>(
            remote: a.solicitudes,
            onReintentar: a.reintentar,
            builder: (_) => _ListaRecibidas(solicitudes: pendientes),
          ),
          RemoteView<List<InterestRequest>>(
            remote: a.solicitudes,
            onReintentar: a.reintentar,
            builder: (_) => _ListaConexiones(conexiones: conexiones),
          ),
          RemoteView(
            remote: a.cotizaciones,
            onReintentar: a.reintentar,
            builder: (_) => cotizaciones.isEmpty
                ? const EmptyState(
                    icono: Icons.request_quote_outlined,
                    titulo: 'Aún no recibes solicitudes de cotización',
                    subtitulo: 'Los compradores con conexión aceptada podrán pedirte precio y condiciones.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cotizaciones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => QuoteCard(
                      cotizacion: cotizaciones[i],
                      verComoVendedor: true,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: cotizaciones[i].id))),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListaRecibidas extends StatefulWidget {
  final List<InterestRequest> solicitudes;
  const _ListaRecibidas({required this.solicitudes});

  @override
  State<_ListaRecibidas> createState() => _ListaRecibidasState();
}

class _ListaRecibidasState extends State<_ListaRecibidas> {
  final Set<String> _procesando = {};

  Future<void> _responder(InterestRequest s, bool aceptar) async {
    if (_procesando.contains(s.id)) return;
    setState(() => _procesando.add(s.id));
    try {
      await context.read<InterestRequestRepository>().responder(s.id, aceptar: aceptar);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _procesando.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final solicitudes = widget.solicitudes;
    if (solicitudes.isEmpty) {
      return const EmptyState(
        icono: Icons.inbox_outlined,
        titulo: 'No tienes solicitudes pendientes',
        subtitulo: 'Cuando un comprador muestre interés en tu café, aparecerá aquí.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _SolicitudRecibida(
        solicitud: solicitudes[i],
        ocupado: _procesando.contains(solicitudes[i].id),
        onResponder: (aceptar) => _responder(solicitudes[i], aceptar),
      ),
    );
  }
}

/// Solicitud recibida: primero QUIÉN está interesado (comprador, tipo y
/// ciudad, cuándo llegó), luego EN QUÉ café y su mensaje, y al final la
/// decisión. «Aceptar» es la acción principal; «Rechazar» queda discreta para
/// que la pantalla no sea una pared de botones.
class _SolicitudRecibida extends StatelessWidget {
  final InterestRequest solicitud;
  final bool ocupado;
  final ValueChanged<bool> onResponder;
  const _SolicitudRecibida({required this.solicitud, required this.ocupado, required this.onResponder});

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    final textTheme = Theme.of(context).textTheme;
    final nombre = s.compradorNombre.isEmpty ? 'Comprador' : s.compradorNombre;
    final perfil = [if (s.compradorTipo != null) s.compradorTipo!, if (s.compradorCiudad != null) s.compradorCiudad!].join(' · ');
    final mensaje = s.mensaje ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                AvatarCircular(fotoUrl: null, nombre: nombre, radius: 22, fontWeight: FontWeight.bold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w800)),
                      if (perfil.isNotEmpty) Text(perfil, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Llegó', style: textTheme.labelSmall),
                    Text(formatFechaN(s.fecha), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                  ],
                ),
              ],
            ),
          ),
          // El café por el que preguntan, en una pieza propia.
          Container(
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
            child: Row(
              children: [
                AppImage(path: s.loteFoto, width: 52, height: 52, borderRadius: BorderRadius.circular(AppRadius.control), ampliable: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Interesado en', style: textTheme.labelSmall),
                      Text(s.loteNombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.2)),
                      if (s.lotePrecioCOP != null) ...[
                        const SizedBox(height: 2),
                        PriceText(valor: s.lotePrecioCOP!, unidad: s.loteUnidad ?? 'kg', size: 15),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (mensaje.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, decoration: BoxDecoration(color: AppColors.coffeeLight, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(mensaje, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, fontStyle: FontStyle.italic, height: 1.4))),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: ocupado ? null : () => onResponder(true),
                    child: ocupado
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Aceptar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextButton(
                    onPressed: ocupado ? null : () => onResponder(false),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(52)),
                    child: const Text('Rechazar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaConexiones extends StatelessWidget {
  final List<InterestRequest> conexiones;
  const _ListaConexiones({required this.conexiones});

  @override
  Widget build(BuildContext context) {
    if (conexiones.isEmpty) {
      return const EmptyState(
        icono: Icons.handshake_outlined,
        titulo: 'Todavía no tienes conexiones comerciales',
        subtitulo: 'Acepta una solicitud para habilitar el chat con ese comprador.',
      );
    }
    final actividad = context.watch<ActivityProvider>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: conexiones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = conexiones[i];
        final noLeido = actividad.tieneNoLeidos(c);
        final cotizaciones = actividad.cotizacionesDeConexion(c.id);
        final porResponder = cotizaciones.any((q) => cotizacionRequiereAccion(q, verComoVendedor: true));
        final perfil = [if (c.compradorTipo != null) c.compradorTipo!, if (c.compradorCiudad != null) c.compradorCiudad!].join(' · ');
        return ConnectionTile(
          foto: c.loteFoto,
          titulo: c.compradorNombre.isEmpty ? 'Comprador' : c.compradorNombre,
          subtitulo: c.loteNombre,
          meta: perfil.isEmpty ? null : perfil,
          noLeido: noLeido,
          estados: [
            if (noLeido) const StatusPill(label: 'Mensaje nuevo', tone: StatusTone.info),
            if (porResponder) const StatusPill(label: 'Cotización por responder', tone: StatusTone.warning, icon: Icons.notifications_active_outlined),
          ],
          onAbrirChat: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(interestRequestId: c.id, otroNombre: c.compradorNombre),
          )),
        );
      },
    );
  }
}
