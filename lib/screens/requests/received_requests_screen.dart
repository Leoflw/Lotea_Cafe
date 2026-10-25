import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/interest_request.dart';
import '../../repositories/interest_request_repository.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [
            Tab(text: 'Interesados (${pendientes.length})'),
            Tab(text: 'Conexiones (${conexiones.length})'),
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
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = solicitudes[i];
        final ocupado = _procesando.contains(s.id);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppImage(path: s.loteFoto, width: 46, height: 46, borderRadius: BorderRadius.circular(12), ampliable: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.compradorNombre.isEmpty ? 'Comprador' : s.compradorNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text([if (s.compradorTipo != null) s.compradorTipo!, if (s.compradorCiudad != null) s.compradorCiudad!].join(' · '),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(formatFechaN(s.fecha), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Interesado en: ${s.loteNombre}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (s.lotePrecioCOP != null)
                  Text(formatCOPPorUnidad(s.lotePrecioCOP!, s.loteUnidad ?? 'kg'), style: const TextStyle(color: AppColors.coffeeDark, fontSize: 12.5)),
                if ((s.mensaje ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('«${s.mensaje}»', style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: ocupado ? null : () => _responder(s, false),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: ocupado ? null : () => _responder(s, true),
                        child: ocupado
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Aceptar'),
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: conexiones.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = conexiones[i];
        return Card(
          child: ListTile(
            leading: AppImage(path: c.loteFoto, width: 44, height: 44, borderRadius: BorderRadius.circular(10), ampliable: false),
            title: Text(c.compradorNombre.isEmpty ? 'Comprador' : c.compradorNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(c.loteNombre),
            trailing: const Icon(Icons.chat_bubble_outline),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(interestRequestId: c.id, otroNombre: c.compradorNombre),
            )),
          ),
        );
      },
    );
  }
}
