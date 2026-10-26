import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/interest_request.dart';
import '../../models/seller_profile.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coffee_lot_card.dart';
import '../../widgets/empty_state.dart';
import 'coffee_lot_edit_screen.dart';
import 'seller_profile_edit_screen.dart';

/// "Mi catálogo" del vendedor (sección 23, 2ª ronda): estadísticas rápidas
/// (cafés publicados, solicitudes pendientes, conexiones) + lista de
/// lotes. Un vendedor puede tener varios cafés (sección 4, 1ª ronda).
class MyCoffeeLotsScreen extends StatelessWidget {
  const MyCoffeeLotsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final usuario = context.read<SessionProvider>().usuario!;
    final perfil = store.obtenerPerfilVendedor(usuario.uid);
    final sellerId = perfil?.id ?? usuario.uid;
    final lotes = store.lotesDeVendedor(sellerId);
    final publicados = lotes.where((l) => l.publicado).length;
    final pendientes = store.solicitudesRecibidas(sellerId).where((s) => s.estado == EstadoSolicitud.pendiente).length;
    final conexiones = store.conexionesVendedor(sellerId).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi catálogo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Editar perfil de mi marca',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerProfileEditScreen())),
          ),
        ],
      ),
      floatingActionButton: perfil == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotEditScreen(sellerId: perfil.id))),
              icon: const Icon(Icons.add),
              label: const Text('Publicar café'),
            ),
      body: perfil == null
          ? EmptyState(
              icono: Icons.storefront_outlined,
              titulo: 'Primero completa el perfil de tu marca',
              subtitulo: 'Nombre, finca, ubicación e historia — así los compradores sabrán quién eres.',
              textoAccion: 'Crear perfil de marca',
              onAccion: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerProfileEditScreen())),
            )
          : Column(
              children: [
                _EncabezadoPerfil(perfil: perfil, publicados: publicados, pendientes: pendientes, conexiones: conexiones),
                Expanded(
                  child: lotes.isEmpty
                      ? EmptyState(
                          icono: Icons.coffee_outlined,
                          titulo: 'Aún no has publicado ningún café',
                          subtitulo: 'Crea tu primer lote para que los compradores puedan encontrarte.',
                          textoAccion: 'Crear mi primer café',
                          onAccion: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotEditScreen(sellerId: perfil.id))),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: lotes.length,
                          itemBuilder: (context, i) {
                            final lote = lotes[i];
                            return CoffeeLotCard(
                              lote: lote,
                              trailing: !lote.publicado
                                  ? const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Chip(
                                        label: Text('Borrador', style: TextStyle(fontSize: 10)),
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: Color(0xFFEFE6DA),
                                      ),
                                    )
                                  : null,
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => CoffeeLotEditScreen(sellerId: perfil.id, loteExistente: lote))),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _EncabezadoPerfil extends StatelessWidget {
  final SellerProfile perfil;
  final int publicados;
  final int pendientes;
  final int conexiones;

  const _EncabezadoPerfil({
    required this.perfil,
    required this.publicados,
    required this.pendientes,
    required this.conexiones,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.coffeeLight,
                child: Text(
                  perfil.nombreMarca.isNotEmpty ? perfil.nombreMarca[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(perfil.nombreMarca, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(perfil.ubicacionCorta, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              if (perfil.verificado) const Icon(Icons.verified, color: AppColors.leafGreen, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('Mis cafés', '$publicados publicados', Icons.coffee_outlined)),
              Expanded(child: _stat('Solicitudes', '$pendientes pendientes', Icons.inbox_outlined)),
              Expanded(child: _stat('Conexiones', '$conexiones', Icons.handshake_outlined)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String etiqueta, String valor, IconData icono) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(icono, size: 17, color: AppColors.coffeeMedium),
          const SizedBox(height: 4),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center),
          Text(etiqueta, style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5)),
        ],
      ),
    );
  }
}
