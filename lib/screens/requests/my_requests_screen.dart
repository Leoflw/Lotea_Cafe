import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/interest_request.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [
            Tab(text: 'Enviadas (${enviadas.length})'),
            Tab(
              child: IndicadorNoLeido(
                visible: a.chatsConNoLeidos > 0,
                child: Text('Conexiones (${conexiones.length})'),
              ),
            ),
            Tab(text: 'Cotizaciones (${cotizaciones.length})'),
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImage(path: s.loteFoto, width: 60, height: 60, borderRadius: BorderRadius.circular(12), ampliable: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.loteNombre.isEmpty ? 'Café' : s.loteNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(s.sellerNombre.isEmpty ? 'Vendedor' : s.sellerNombre, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      if (s.lotePrecioCOP != null)
                        Text(formatCOPPorUnidad(s.lotePrecioCOP!, s.loteUnidad ?? 'kg'),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coffeeDark, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(formatFechaN(s.fecha), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ChipEstado(estado: s.estado),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: s.coffeeLotId))),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 28)),
                      child: const Text('Ver café', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChipEstado extends StatelessWidget {
  final EstadoSolicitud estado;
  const _ChipEstado({required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      EstadoSolicitud.pendiente => AppColors.coffeeMedium,
      EstadoSolicitud.aceptada => AppColors.leafGreen,
      EstadoSolicitud.rechazada => AppColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(estado.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppImage(path: c.loteFoto, width: 46, height: 46, borderRadius: BorderRadius.circular(12), ampliable: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.sellerNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(c.loteNombre, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (cotizaciones.isNotEmpty)
                      Text(etiquetaCotizaciones(cotizaciones.length), style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: IndicadorNoLeido(visible: actividad.tieneNoLeidos(c), child: const Icon(Icons.chat_bubble_outline, size: 18)),
                        label: Text(actividad.tieneNoLeidos(c) ? 'Chat · nuevo' : 'Chat'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChatScreen(interestRequestId: c.id, otroNombre: c.sellerNombre),
                        )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.request_quote_outlined, size: 18),
                        label: const Text('Cotizar'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: c))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
