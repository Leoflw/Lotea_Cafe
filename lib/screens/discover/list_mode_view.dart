import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_lot.dart';
import '../../widgets/coffee_lot_card.dart';
import '../../widgets/empty_state.dart';
import '../seller/seller_detail_screen.dart';

/// Modo "Lista": para quienes prefieran explorar sin usar el gesto de
/// swipe (sección 8 del plan de evolución).
class ListModeView extends StatelessWidget {
  final List<CoffeeLot> lotes;

  const ListModeView({super.key, required this.lotes});

  @override
  Widget build(BuildContext context) {
    if (lotes.isEmpty) {
      return const EmptyState(
        icono: Icons.coffee_outlined,
        titulo: 'No hay cafés que coincidan',
        subtitulo: 'Prueba ajustando los filtros de búsqueda.',
      );
    }
    final store = context.read<MockStore>();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lotes.length,
      itemBuilder: (context, i) {
        final lote = lotes[i];
        final vendedor = store.perfilVendedorPorId(lote.sellerId);
        return CoffeeLotCard(
          lote: lote,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SellerDetailScreen(sellerId: lote.sellerId, loteDestacadoId: lote.id),
            ),
          ),
          trailing: vendedor?.verificado == true
              ? const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.verified, color: Colors.green, size: 18),
                )
              : null,
        );
      },
    );
  }
}
