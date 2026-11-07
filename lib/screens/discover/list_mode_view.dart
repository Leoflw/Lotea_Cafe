import 'package:flutter/material.dart';
import '../../models/coffee_lot.dart';
import '../../widgets/coffee_lot_card.dart';
import '../seller/seller_detail_screen.dart';

/// Modo "Lista": explorar sin swipe. Los estados vacíos (sin resultados,
/// sin filtros…) los resuelve Descubrir, que conoce su causa.
class ListModeView extends StatelessWidget {
  final List<CoffeeLot> lotes;
  final VoidCallback onRegresoDeDetalle;

  const ListModeView({super.key, required this.lotes, required this.onRegresoDeDetalle});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: lotes.length,
      itemBuilder: (context, i) {
        final lote = lotes[i];
        return CoffeeLotCard(
          lote: lote,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: lote.sellerId, loteDestacadoId: lote.id)),
            );
            onRegresoDeDetalle();
          },
        );
      },
    );
  }
}
