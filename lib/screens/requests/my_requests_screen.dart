import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/interest_request.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/empty_state.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import '../chat/chat_screen.dart';
import '../chat/quote_request_screen.dart';

/// "Mis solicitudes" del comprador: enviadas + conexiones establecidas,
/// con tarjetas completas (café, vendedor, precio, fecha, estado) según
/// la sección 17 de la 2ª ronda.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    final enviadas = store.solicitudesEnviadas(uid);
    final conexiones = store.conexionesComprador(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [Tab(text: 'Enviadas (${enviadas.length})'), Tab(text: 'Conexiones (${conexiones.length})')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_ListaEnviadas(solicitudes: enviadas), _ListaConexiones(conexiones: conexiones)],
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
    final store = context.read<MockStore>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = solicitudes[i];
        final lote = store.lotePorId(s.coffeeLotId);
        final vendedor = store.perfilVendedorPorId(s.sellerId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImage(
                  path: lote != null && lote.fotos.isNotEmpty ? lote.fotos.first : null,
                  width: 60,
                  height: 60,
                  borderRadius: BorderRadius.circular(12),
                  ampliable: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lote?.nombre ?? 'Café', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(vendedor?.nombreMarca ?? 'Vendedor', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      if (lote != null)
                        Text(formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coffeeDark, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(formatFecha(s.fecha), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _chipEstado(s.estado),
                    const SizedBox(height: 8),
                    if (lote != null)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: lote.id))),
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

  Widget _chipEstado(EstadoSolicitud estado) {
    Color color;
    switch (estado) {
      case EstadoSolicitud.pendiente:
        color = AppColors.coffeeMedium;
      case EstadoSolicitud.aceptada:
        color = AppColors.leafGreen;
      case EstadoSolicitud.rechazada:
        color = AppColors.danger;
    }
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
    final store = context.read<MockStore>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: conexiones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = conexiones[i];
        final lote = store.lotePorId(c.coffeeLotId);
        final vendedor = store.perfilVendedorPorId(c.sellerId);
        final nombre = vendedor?.nombreMarca ?? 'Vendedor';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppImage(
                      path: lote != null && lote.fotos.isNotEmpty ? lote.fotos.first : null,
                      width: 50,
                      height: 50,
                      borderRadius: BorderRadius.circular(12),
                      ampliable: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Interesado en: ${lote?.nombre ?? '—'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          if (lote != null)
                            Text(formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                                style: const TextStyle(color: AppColors.coffeeDark, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (lote != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: lote.id))),
                          child: const Text('Ver café', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(interestRequestId: c.id, otroNombre: nombre))),
                        child: const Text('Abrir conversación', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuoteRequestScreen(conexion: c))),
                    icon: const Icon(Icons.request_quote_outlined, size: 16),
                    label: const Text('Solicitar cotización', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
