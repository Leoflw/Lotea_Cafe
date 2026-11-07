import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/interest_request.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/connection_tile.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/unread_badge.dart';
import '../chat/chat_screen.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import '../quotes/quote_detail_screen.dart';
import '../quotes/quote_request_screen.dart';
import '../quotes/quote_widgets.dart';

/// Comprador: solicitudes enviadas, conexiones comerciales y cotizaciones.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ActivityProvider>();
    final enviadas = a.listaSolicitudes;
    final conexiones = a.conexiones;
    final cotizaciones = a.listaCotizaciones;
    final cotizacionPorResponder = cotizaciones.any((q) => cotizacionRequiereAccion(q, verComoVendedor: false));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          unselectedLabelColor: AppColors.inkMuted,
          indicatorColor: AppColors.coffeeMedium,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Enviadas (${enviadas.length})'),
            Tab(
              child: IndicadorNoLeido(
                visible: a.chatsConNoLeidos > 0,
                child: Text('Conexiones (${conexiones.length})'),
              ),
            ),
            Tab(
              child: IndicadorNoLeido(
                visible: cotizacionPorResponder,
                etiqueta: 'Cotizaciones con una oferta por responder',
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
            builder: (_) => _ListaEnviadas(solicitudes: enviadas),
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
                    titulo: 'Aún no has pedido cotizaciones',
                    subtitulo: 'Cuando un vendedor acepte tu interés, podrás solicitar precio y condiciones desde la pestaña Conexiones.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cotizaciones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => QuoteCard(
                      cotizacion: cotizaciones[i],
                      verComoVendedor: false,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: cotizaciones[i].id))),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Solicitudes que el comprador envió, con lo que puede hacer a continuación
/// según su estado: pendiente (esperar), aceptada (ya puede chatear y cotizar)
/// o rechazada.
class _ListaEnviadas extends StatelessWidget {
  final List<InterestRequest> solicitudes;
  const _ListaEnviadas({required this.solicitudes});

  @override
  Widget build(BuildContext context) {
    if (solicitudes.isEmpty) {
      return const EmptyState(
        icono: Icons.outbox_outlined,
        titulo: 'No tienes solicitudes activas',
        subtitulo: 'Cuando algo te interese, toca "Me interesa" en el perfil de un vendedor.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = solicitudes[i];
        final aceptada = s.estado == EstadoSolicitud.aceptada;
        return ActivityCard(
          foto: s.loteFoto,
          titulo: s.loteNombre.isEmpty ? 'Café' : s.loteNombre,
          subtitulo: s.sellerNombre.isEmpty ? 'Vendedor' : s.sellerNombre,
          detalles: [
            if (s.lotePrecioCOP != null)
              Text(formatCOPPorUnidad(s.lotePrecioCOP!, s.loteUnidad ?? 'kg'),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coffeeDark, fontSize: 14)),
            if (s.estado == EstadoSolicitud.pendiente)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Esperando la respuesta del vendedor', style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
          estado: RequestStatusChip(estado: s.estado),
          fecha: 'Enviada ${formatFechaN(s.fecha)}',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: s.coffeeLotId))),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(40, 28)),
            child: const Text('Ver café', style: TextStyle(fontSize: 12)),
          ),
          // Una solicitud aceptada es una conexión: se puede abrir su chat.
          avisoAccion: aceptada ? 'Aceptada: ya puedes chatear y pedir cotización' : null,
          avisoTono: StatusTone.success,
          avisoIcono: Icons.chat_bubble_outline,
          onTap: aceptada
              ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(interestRequestId: s.id, otroNombre: s.sellerNombre),
                  ))
              : null,
        );
      },
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
        titulo: 'Cuando un vendedor acepte tu interés, aparecerá aquí',
        subtitulo: 'Desde ahí podrás abrir el chat y solicitar una cotización.',
      );
    }
    final actividad = context.watch<ActivityProvider>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: conexiones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = conexiones[i];
        final cotizaciones = actividad.cotizacionesDeConexion(c.id);
        final noLeido = actividad.tieneNoLeidos(c);
        final porResponder = cotizaciones.any((q) => cotizacionRequiereAccion(q, verComoVendedor: false));
        return ConnectionTile(
          foto: c.loteFoto,
          titulo: c.sellerNombre.isEmpty ? 'Vendedor' : c.sellerNombre,
          subtitulo: c.loteNombre,
          meta: c.fecha == null ? null : 'Interés enviado el ${formatFecha(c.fecha!)}',
          noLeido: noLeido,
          estados: [
            if (noLeido) const StatusPill(label: 'Mensaje nuevo', tone: StatusTone.info),
            if (porResponder) const StatusPill(label: 'Oferta por responder', tone: StatusTone.warning, icon: Icons.notifications_active_outlined),
            if (cotizaciones.isNotEmpty && !porResponder) StatusPill(label: etiquetaCotizaciones(cotizaciones.length), tone: StatusTone.neutral),
          ],
          accionSecundaria: TextButton.icon(
            icon: const Icon(Icons.request_quote_outlined, size: 18),
            label: const Text('Cotizar'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: c))),
          ),
          onAbrirChat: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(interestRequestId: c.id, otroNombre: c.sellerNombre),
          )),
        );
      },
    );
  }
}
