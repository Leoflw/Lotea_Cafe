import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';
import '../../widgets/badges.dart';
import '../../widgets/coffee_lot_card.dart';
import '../../widgets/empty_state.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import '../seller/seller_detail_screen.dart';

/// Cafés y vendedores guardados por el comprador, separados en dos
/// pestañas (sección 16, 2ª ronda). No se mezcla con las solicitudes
/// comerciales: guardar es solo para revisar después.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> with SingleTickerProviderStateMixin {
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
    final cafes = store.cafesGuardados(uid);
    final vendedores = store.vendedoresGuardados(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardados'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [Tab(text: 'Cafés (${cafes.length})'), Tab(text: 'Vendedores (${vendedores.length})')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          cafes.isEmpty
              ? const EmptyState(
                  icono: Icons.bookmark_border,
                  titulo: 'Todavía no has guardado cafés',
                  subtitulo: 'Explora el catálogo y guarda los que quieras revisar después.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: cafes.length,
                  itemBuilder: (context, i) => CoffeeLotCard(
                    lote: cafes[i],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: cafes[i].id))),
                  ),
                ),
          vendedores.isEmpty
              ? const EmptyState(
                  icono: Icons.storefront_outlined,
                  titulo: 'Todavía no has guardado vendedores',
                  subtitulo: 'Guarda los productores que te interesen para volver a su perfil fácilmente.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: vendedores.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final v = vendedores[i];
                    final numCafes = store.lotesDeVendedor(v.id).where((l) => l.publicado).length;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: v.id))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              AppImage(
                                path: v.fotoPrincipal,
                                width: 56,
                                height: 56,
                                borderRadius: BorderRadius.circular(14),
                                ampliable: false,
                                iconoPlaceholder: Icons.storefront_outlined,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text(v.nombreMarca, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                        if (v.verificado) const Icon(Icons.verified, size: 15, color: AppColors.leafGreen),
                                      ],
                                    ),
                                    Text(v.ubicacionCorta, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        RatingBadge(calificacion: v.calificacionPromedio, color: AppColors.coffeeDark),
                                        const SizedBox(width: 10),
                                        Text('$numCafes cafés disponibles', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
