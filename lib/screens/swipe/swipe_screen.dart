import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_profile.dart';
import '../../models/match_model.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/swipe_card.dart';
import '../chat/chat_screen.dart';
import 'filters_sheet.dart';

/// Pantalla "Home" del comprador: navega perfiles de vendedores con gestos
/// tipo swipe (derecha = like, izquierda = descartar). Los perfiles vienen
/// del MockStore (memoria), incluye 5 fincas de demo precargadas.
class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _controller = CardSwiperController();
  List<CoffeeProfile> _perfiles = [];
  SwipeFilters _filtros = const SwipeFilters();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarPerfiles());
  }

  void _cargarPerfiles() {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    setState(() {
      _perfiles = store.obtenerPerfilesParaDescubrir(
        compradorId: uid,
        variedades: _filtros.variedades.isEmpty ? null : _filtros.variedades,
        precioMax: _filtros.precioMax,
        proceso: _filtros.proceso,
      );
    });
  }

  void _onSwipe(int index, bool esLike) {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    final perfil = _perfiles[index];
    final match = store.registrarSwipe(compradorId: uid, perfil: perfil, esLike: esLike);
    if (match != null) _mostrarMatch(match, perfil);
  }

  void _mostrarMatch(MatchModel match, CoffeeProfile perfil) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¡Es un match! ☕️'),
        content: Text(
          'Hiciste match con ${perfil.nombreVendedor}. Ya puedes chatear para negociar tu compra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Seguir explorando'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chatId: match.chatId,
                    otroNombre: perfil.nombreVendedor,
                  ),
                ),
              );
            },
            child: const Text('Ir al chat'),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirFiltros() async {
    final resultado = await mostrarFiltros(context, _filtros);
    if (resultado != null) {
      _filtros = resultado;
      _cargarPerfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descubrir café'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Filtros',
            onPressed: _abrirFiltros,
          ),
        ],
      ),
      body: _perfiles.isEmpty
          ? _EstadoVacio(onReintentar: _cargarPerfiles)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  Expanded(
                    child: CardSwiper(
                      controller: _controller,
                      cardsCount: _perfiles.length,
                      numberOfCardsDisplayed: _perfiles.length < 2 ? 1 : 2,
                      backCardOffset: const Offset(0, 24),
                      padding: EdgeInsets.zero,
                      onSwipe: (previousIndex, currentIndex, direction) {
                        final esLike = direction == CardSwiperDirection.right;
                        _onSwipe(previousIndex, esLike);
                        return true;
                      },
                      cardBuilder: (context, index, _, __) =>
                          SwipeCard(perfil: _perfiles[index]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BotonAccion(
                        icono: Icons.close,
                        color: AppColors.danger,
                        onTap: () => _controller.swipe(CardSwiperDirection.left),
                      ),
                      const SizedBox(width: 28),
                      _BotonAccion(
                        icono: Icons.favorite,
                        color: AppColors.like,
                        onTap: () => _controller.swipe(CardSwiperDirection.right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  final IconData icono;
  final Color color;
  final VoidCallback onTap;

  const _BotonAccion({required this.icono, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icono, color: color, size: 30),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final VoidCallback onReintentar;
  const _EstadoVacio({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.coffee_outlined, size: 64, color: AppColors.coffeeLight),
            const SizedBox(height: 16),
            const Text(
              'No hay más perfiles por ahora.\nAjusta tus filtros o vuelve más tarde.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onReintentar, child: const Text('Actualizar')),
          ],
        ),
      ),
    );
  }
}
