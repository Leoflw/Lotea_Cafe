import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../models/favorite.dart';
import '../../models/seller_profile.dart';
import '../../repositories/coffee_lot_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../repositories/seller_repository.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';
import '../../widgets/coffee_lot_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
import '../coffee/coffee_lot_detail_screen.dart';
import '../seller/seller_detail_screen.dart';

/// Cafés y vendedores guardados (favoritos). Guardar no implica interés
/// comercial. Los favoritos son referencias: los datos del café o vendedor
/// se leen de Firestore, así que siempre están al día; si un café se
/// despublicó, simplemente deja de aparecer.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _firma = '';
  Future<List<CoffeeLot>>? _cafes;
  Future<List<SellerProfile>>? _vendedores;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<List<SellerProfile>> _cargarVendedores(List<String> ids) async {
    final repo = context.read<SellerRepository>();
    final res = await Future.wait(ids.map(repo.obtener));
    return res.whereType<SellerProfile>().toList();
  }

  void _preparar(ActivityProvider a, {bool forzar = false}) {
    final idsC = a.idsFavoritos(TipoFavorito.cafe);
    final idsV = a.idsFavoritos(TipoFavorito.vendedor);
    final firma = '${idsC.join(',')}|${idsV.join(',')}';
    if (!forzar && firma == _firma && _cafes != null) return;
    _firma = firma;
    _cafes = idsC.isEmpty ? Future.value(<CoffeeLot>[]) : context.read<CoffeeLotRepository>().publicadosPorIds(idsC);
    _vendedores = idsV.isEmpty ? Future.value(<SellerProfile>[]) : _cargarVendedores(idsV);
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ActivityProvider>();
    if (a.favoritos.listo) _preparar(a);
    final nC = a.idsFavoritos(TipoFavorito.cafe).length;
    final nV = a.idsFavoritos(TipoFavorito.vendedor).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardados'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.coffeeMedium,
          indicatorColor: AppColors.coffeeMedium,
          tabs: [Tab(text: 'Cafés ($nC)'), Tab(text: 'Vendedores ($nV)')],
        ),
      ),
      body: RemoteView(
        remote: a.favoritos,
        onReintentar: a.reintentar,
        builder: (_) => TabBarView(
          controller: _tabs,
          children: [
            nC == 0
                ? const EmptyState(
                    icono: Icons.bookmark_border,
                    titulo: 'Todavía no has guardado cafés',
                    subtitulo: 'Explora el catálogo y guarda los que quieras revisar después.',
                  )
                : _Futuro<List<CoffeeLot>>(
                    futuro: _cafes!,
                    onReintentar: () => setState(() => _preparar(a, forzar: true)),
                    builder: (cafes) => cafes.isEmpty
                        ? const EmptyState(
                            icono: Icons.coffee_outlined,
                            titulo: 'Tus cafés guardados ya no están disponibles',
                            subtitulo: 'Los vendedores pueden despublicar sus lotes.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: cafes.length,
                            itemBuilder: (context, i) => CoffeeLotCard(
                              lote: cafes[i],
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: cafes[i].id))),
                            ),
                          ),
                  ),
            nV == 0
                ? const EmptyState(
                    icono: Icons.storefront_outlined,
                    titulo: 'Todavía no has guardado vendedores',
                    subtitulo: 'Guarda los productores que te interesen para volver a su perfil fácilmente.',
                  )
                : _Futuro<List<SellerProfile>>(
                    futuro: _vendedores!,
                    onReintentar: () => setState(() => _preparar(a, forzar: true)),
                    builder: (vendedores) => ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: vendedores.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _TarjetaVendedor(v: vendedores[i]),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _Futuro<T> extends StatelessWidget {
  final Future<T> futuro;
  final Widget Function(T) builder;
  final VoidCallback onReintentar;
  const _Futuro({required this.futuro, required this.builder, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: futuro,
      builder: (context, snap) {
        if (snap.hasError) return RepoErrorView(error: RepoException.desde(snap.error!), onReintentar: onReintentar);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.coffeeMedium));
        return builder(snap.data as T);
      },
    );
  }
}

class _TarjetaVendedor extends StatelessWidget {
  final SellerProfile v;
  const _TarjetaVendedor({required this.v});

  @override
  Widget build(BuildContext context) {
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
                    FutureBuilder<int>(
                      future: context.read<CoffeeLotRepository>().contarPublicados(v.id),
                      builder: (c, s) => Text(
                        s.hasData ? '${s.data} cafés disponibles' : (s.hasError ? '' : '…'),
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
