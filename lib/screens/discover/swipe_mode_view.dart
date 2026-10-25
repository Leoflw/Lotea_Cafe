import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/interest_dialog.dart';
import '../../widgets/swipe_card.dart';
import '../seller/seller_detail_screen.dart';

/// Modo "Tarjetas": el swipe como mecanismo OPCIONAL de descubrimiento.
///
/// Acciones (sin redundancia): tocar la tarjeta o su botón "Ver perfil" abre
/// el perfil; debajo hay solo dos decisiones — Descartar y Me interesa — con
/// etiqueta de texto además del ícono. El gesto equivale a esos botones.
class SwipeModeView extends StatefulWidget {
  final List<CoffeeLot> lotes;
  final VoidCallback onCambioLista;

  /// Se llama al volver del perfil para que Descubrir recargue si el
  /// catálogo cambió (p. ej. se envió una solicitud desde el detalle).
  final VoidCallback onRegresoDeDetalle;

  const SwipeModeView({
    super.key,
    required this.lotes,
    required this.onCambioLista,
    required this.onRegresoDeDetalle,
  });

  @override
  State<SwipeModeView> createState() => _SwipeModeViewState();
}

class _SwipeModeViewState extends State<SwipeModeView> {
  static const int _interaccionesParaOcultarPista = 3;

  final _controller = CardSwiperController();
  int _interacciones = 0;

  bool get _mostrarPista => _interacciones < _interaccionesParaOcultarPista;

  Future<void> _abrirPerfil(CoffeeLot lote) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: lote.sellerId, loteDestacadoId: lote.id)),
    );
    if (mounted) widget.onRegresoDeDetalle();
  }

  void _descartar(int index) {
    final actividad = context.read<ActivityProvider>();
    actividad.descartar(widget.lotes[index].id);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Café descartado'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            actividad.deshacerUltimoDescarte();
            _controller.undo(); // devuelve también la tarjeta al mazo
          },
        ),
      ),
    );
  }

  Future<void> _meInteresa(int index) async {
    final enviada = await mostrarDialogoInteres(context: context, lote: widget.lotes[index]);
    // Si canceló (o ya existía), la tarjeta vuelve al mazo: no se pierde un café sin decidir.
    if (!enviada && mounted) _controller.undo();
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Expanded(
            child: CardSwiper(
              controller: _controller,
              cardsCount: widget.lotes.length,
              numberOfCardsDisplayed: widget.lotes.length < 2 ? 1 : 2,
              backCardOffset: const Offset(0, 18),
              padding: EdgeInsets.zero,
              onSwipe: (previousIndex, currentIndex, direction) {
                // Solo izquierda (descartar) y derecha (me interesa) deciden
                // algo. Arriba/abajo se cancelan: la tarjeta vuelve al mazo.
                if (direction != CardSwiperDirection.left && direction != CardSwiperDirection.right) {
                  return false;
                }
                if (direction == CardSwiperDirection.left) {
                  _descartar(previousIndex);
                } else if (direction == CardSwiperDirection.right) {
                  _meInteresa(previousIndex);
                }
                if (_mostrarPista) setState(() => _interacciones++);
                return true;
              },
              cardBuilder: (context, index, _, __) {
                final lote = widget.lotes[index];
                return SwipeCard(
                  lote: lote,
                  mostrarPista: _mostrarPista && index == 0,
                  onVerPerfil: () => _abrirPerfil(lote),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _controller.swipe(CardSwiperDirection.left),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Descartar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _controller.swipe(CardSwiperDirection.right),
                  icon: const Icon(Icons.coffee_outlined, size: 18),
                  label: const Text('Me interesa'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: AppColors.leafGreen,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
