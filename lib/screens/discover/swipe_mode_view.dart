import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_lot.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/interest_dialog.dart';
import '../../widgets/swipe_card.dart';
import '../seller/seller_detail_screen.dart';

/// Modo "Tarjetas": mecánica de swipe conservada como mecanismo OPCIONAL de
/// descubrimiento rápido, no como el centro de la app (sección 7 y 13,
/// 2ª ronda). Acciones con etiqueta de texto (no solo íconos) para
/// accesibilidad, y "Deshacer" tras un descarte (sección 15).
class SwipeModeView extends StatefulWidget {
  final List<CoffeeLot> lotes;
  final VoidCallback onCambioLista;

  const SwipeModeView({super.key, required this.lotes, required this.onCambioLista});

  @override
  State<SwipeModeView> createState() => _SwipeModeViewState();
}

class _SwipeModeViewState extends State<SwipeModeView> {
  final _controller = CardSwiperController();

  void _abrirPerfil(CoffeeLot lote) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: lote.sellerId, loteDestacadoId: lote.id)),
    );
  }

  void _descartar(int index) {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    final loteId = widget.lotes[index].id;
    store.descartarLote(compradorId: uid, coffeeLotId: loteId);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Café descartado'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => store.deshacerUltimoDescarte(uid),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _meInteresa(int index) async {
    final uid = context.read<SessionProvider>().usuario!.uid;
    await mostrarDialogoInteres(context: context, lote: widget.lotes[index], compradorId: uid);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lotes.isEmpty) {
      return EmptyState(
        icono: Icons.coffee_outlined,
        titulo: 'No hay más cafés para descubrir',
        subtitulo: 'Ajusta tus filtros o revisa el modo lista.',
        textoAccion: 'Ver en modo lista',
        onAccion: widget.onCambioLista,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          Expanded(
            child: CardSwiper(
              controller: _controller,
              cardsCount: widget.lotes.length,
              numberOfCardsDisplayed: widget.lotes.length < 2 ? 1 : 2,
              backCardOffset: const Offset(0, 24),
              padding: EdgeInsets.zero,
              onSwipe: (previousIndex, currentIndex, direction) {
                if (direction == CardSwiperDirection.left) {
                  _descartar(previousIndex);
                } else if (direction == CardSwiperDirection.right) {
                  _meInteresa(previousIndex);
                }
                return true;
              },
              cardBuilder: (context, index, _, __) {
                final lote = widget.lotes[index];
                final vendedor = context.read<MockStore>().perfilVendedorPorId(lote.sellerId);
                return SwipeCard(lote: lote, vendedor: vendedor, onVerPerfil: () => _abrirPerfil(lote));
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _boton(
                icono: Icons.close,
                etiqueta: 'Descartar',
                color: AppColors.danger,
                tooltip: 'Descartar este café',
                onTap: () => _controller.swipe(CardSwiperDirection.left),
              ),
              _boton(
                icono: Icons.storefront_outlined,
                etiqueta: 'Ver perfil',
                color: AppColors.coffeeMedium,
                tooltip: 'Ver perfil completo del vendedor',
                onTap: () => _abrirPerfil(widget.lotes.first),
                grande: true,
              ),
              _boton(
                icono: Icons.coffee,
                etiqueta: 'Me interesa',
                color: AppColors.leafGreen,
                tooltip: 'Enviar solicitud de contacto',
                onTap: () => _controller.swipe(CardSwiperDirection.right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boton({
    required IconData icono,
    required String etiqueta,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    bool grande = false,
  }) {
    return Semantics(
      button: true,
      label: etiqueta,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(grande ? 15 : 14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Icon(icono, color: color, size: grande ? 24 : 22),
                ),
                const SizedBox(height: 4),
                Text(etiqueta, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
