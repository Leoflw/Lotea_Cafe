import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/seller_profile.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/avatar_logic.dart';
import '../../utils/format_utils.dart';
import '../../widgets/avatar_circular.dart';
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
    final a = context.watch<ActivityProvider>();
    if (a.perfilVendedor.cargando || a.lotesPropios.cargando) {
      return Scaffold(appBar: AppBar(title: const Text('Mi catálogo')), body: const Center(child: CircularProgressIndicator()));
    }
    if (a.perfilVendedor.fallo || a.lotesPropios.fallo) {
      final e = (a.perfilVendedor.error ?? a.lotesPropios.error)!;
      return Scaffold(appBar: AppBar(title: const Text('Mi catálogo')), body: RepoErrorView(error: e, onReintentar: a.reintentar));
    }
    final perfil = a.perfilVendedor.data;
    final lotes = a.listaLotesPropios;
    final publicados = a.lotesPublicados;
    final pendientes = a.pendientes.length;
    final conexiones = a.conexiones.length;

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
              AvatarCircular(
                fotoUrl: AvatarLogic.fotoDeMarca(perfil),
                nombre: perfil.nombreMarca,
                radius: 22,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(perfil.nombreMarca, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(perfil.ubicacionCorta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              if (perfil.verificado) const Icon(Icons.verified, color: AppColors.leafGreen, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _stat(etiquetaCafesPublicados(publicados), Icons.coffee_outlined)),
                Expanded(child: _stat(etiquetaSolicitudesPendientes(pendientes), Icons.inbox_outlined)),
                Expanded(child: _stat(etiquetaConexiones(conexiones), Icons.handshake_outlined, ultimo: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String texto, IconData icono, {bool ultimo = false}) {
    return Container(
      margin: EdgeInsets.only(right: ultimo ? 0 : 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 18, color: AppColors.coffeeMedium),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
