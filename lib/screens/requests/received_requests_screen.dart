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

/// "Solicitudes recibidas" del vendedor: compradores interesados en sus
/// cafés, con acciones Aceptar/Rechazar, más sus conexiones activas.
class ReceivedRequestsScreen extends StatefulWidget {
  const ReceivedRequestsScreen({super.key});

  @override
  State<ReceivedRequestsScreen> createState() => _ReceivedRequestsScreenState();
}

class _ReceivedRequestsScreenState extends State<ReceivedRequestsScreen> with SingleTickerProviderStateMixin {
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
    final perfil = store.obtenerPerfilVendedor(uid);
    final sellerId = perfil?.id ?? uid;

    final recibidas = store.solicitudesRecibidas(sellerId).where((s) => s.estado == EstadoSolicitud.pendiente).toList();
    final conexiones = store.conexionesVendedor(sellerId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [Tab(text: 'Compradores interesados (${recibidas.length})'), Tab(text: 'Conexiones (${conexiones.length})')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [_ListaRecibidas(solicitudes: recibidas), _ListaConexiones(conexiones: conexiones)]),
    );
  }
}

class _ListaRecibidas extends StatelessWidget {
  final List<InterestRequest> solicitudes;
  const _ListaRecibidas({required this.solicitudes});

  @override
  Widget build(BuildContext context) {
    if (solicitudes.isEmpty) {
      return const EmptyState(
        icono: Icons.inbox_outlined,
        titulo: 'No tienes solicitudes pendientes',
        subtitulo: 'Cuando un comprador muestre interés en tu café, aparecerá aquí.',
      );
    }
    final store = context.read<MockStore>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: solicitudes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = solicitudes[i];
        final comprador = store.usuarioPorId(s.compradorId);
        final lote = store.lotePorId(s.coffeeLotId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppImage(
                      path: lote != null && lote.fotos.isNotEmpty ? lote.fotos.first : null,
                      width: 46,
                      height: 46,
                      borderRadius: BorderRadius.circular(12),
                      ampliable: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(comprador?.nombre ?? 'Comprador', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            [
                              if (comprador?.tipoComprador != null) comprador!.tipoComprador!.label,
                              if (comprador?.ciudad != null) comprador!.ciudad!,
                            ].join(' · '),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(formatFecha(s.fecha), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Interesado en: ${lote?.nombre ?? 'café'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (lote != null)
                  Text(formatCOPPorUnidad(lote.precioCOP, lote.unidad), style: const TextStyle(color: AppColors.coffeeDark, fontSize: 12.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => store.rechazarSolicitud(s.id),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(onPressed: () => store.aceptarSolicitud(s.id), child: const Text('Aceptar')),
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
    final store = context.read<MockStore>();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: conexiones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = conexiones[i];
        final comprador = store.usuarioPorId(c.compradorId);
        final lote = store.lotePorId(c.coffeeLotId);
        final nombre = comprador?.nombre ?? 'Comprador';
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
                      width: 46,
                      height: 46,
                      borderRadius: BorderRadius.circular(12),
                      ampliable: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Café: ${lote?.nombre ?? '—'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
