import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/favorite.dart';
import '../../models/seller_profile.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';
import '../../widgets/badges.dart';
import '../../widgets/coffee_lot_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/fullscreen_image_viewer.dart';
import '../../widgets/interest_dialog.dart';
import '../coffee/coffee_lot_detail_screen.dart';

/// Perfil completo del vendedor. Orden de la sección 6 de la 2ª ronda:
/// foto principal → nombre de marca → ubicación → verificación →
/// reputación → resumen → fotografías → historia → información de
/// producción → cafés disponibles. Incluye sección de confianza (7) y
/// galería ampliable con [FullscreenImageViewer] (sección 2).
class SellerDetailScreen extends StatelessWidget {
  final String sellerId;
  final String? loteDestacadoId;

  const SellerDetailScreen({super.key, required this.sellerId, this.loteDestacadoId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final session = context.read<SessionProvider>();
    final vendedor = store.perfilVendedorPorId(sellerId);

    if (vendedor == null) {
      return const Scaffold(body: EmptyState(icono: Icons.error_outline, titulo: 'Vendedor no encontrado'));
    }

    final lotes = store.lotesDeVendedor(sellerId).where((l) => l.publicado).toList();
    final galeriaCompleta = [
      if (vendedor.fotoPrincipal != null) vendedor.fotoPrincipal!,
      ...vendedor.galeria,
    ];
    final esGuardado = session.usuario != null &&
        !session.esVendedor &&
        store.esFavorito(compradorId: session.usuario!.uid, tipo: TipoFavorito.vendedor, refId: sellerId);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.coffeeDark,
            actions: [
              if (session.usuario != null && !session.esVendedor)
                IconButton(
                  icon: Icon(esGuardado ? Icons.bookmark : Icons.bookmark_border, color: Colors.white),
                  tooltip: 'Guardar vendedor',
                  onPressed: () => store.alternarFavorito(compradorId: session.usuario!.uid, tipo: TipoFavorito.vendedor, refId: sellerId),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: GestureDetector(
                onTap: galeriaCompleta.isEmpty
                    ? null
                    : () => FullscreenImageViewer.abrir(context, images: galeriaCompleta, initialIndex: 0),
                child: _Cabecera(vendedor: vendedor, tieneGaleria: galeriaCompleta.isNotEmpty),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ---------- NOMBRE + UBICACIÓN + VERIFICACIÓN + REPUTACIÓN ----------
                Row(
                  children: [
                    Expanded(child: Text(vendedor.nombreMarca, style: Theme.of(context).textTheme.headlineSmall)),
                    if (vendedor.verificado) const VerifiedBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(vendedor.ubicacionCorta, style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(width: 14),
                    RatingBadge(calificacion: vendedor.calificacionPromedio, color: AppColors.coffeeDark),
                  ],
                ),

                // ---------- RESUMEN ----------
                if (vendedor.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(vendedor.descripcion, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                ],

                // ---------- CONFIANZA (sección 7) ----------
                const SizedBox(height: 20),
                _SeccionConfianza(vendedor: vendedor, numLotes: lotes.length),

                // ---------- FOTOGRAFÍAS ----------
                if (galeriaCompleta.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _seccion('Fotografías'),
                      Text('${galeriaCompleta.length} foto${galeriaCompleta.length == 1 ? '' : 's'}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: galeriaCompleta.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => AppImage(
                        path: galeriaCompleta[i],
                        galeria: galeriaCompleta,
                        indiceEnGaleria: i,
                        width: 120,
                        height: 120,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],

                // ---------- HISTORIA ----------
                if (vendedor.historia.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _seccion('Sobre el productor'),
                  Text(vendedor.historia, style: const TextStyle(fontSize: 14, height: 1.5)),
                ],

                // ---------- INFORMACIÓN DE PRODUCCIÓN ----------
                const SizedBox(height: 24),
                _seccion('Información del productor'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.coffeeLight)),
                  child: Wrap(
                    runSpacing: 12,
                    children: [
                      if (vendedor.aniosProduciendo != null)
                        _datoProductor(Icons.history, 'Años produciendo', '${vendedor.aniosProduciendo}'),
                      if (vendedor.tipoProduccion != null)
                        _datoProductor(Icons.agriculture_outlined, 'Tipo de producción', vendedor.tipoProduccion!),
                      _datoProductor(Icons.location_on_outlined, 'Ubicación', vendedor.ubicacionCorta),
                      _datoProductor(Icons.coffee_outlined, 'Cafés publicados', '${lotes.length}'),
                      if (vendedor.numOperaciones > 0)
                        _datoProductor(Icons.handshake_outlined, 'Operaciones realizadas', '${vendedor.numOperaciones}'),
                    ],
                  ),
                ),

                // ---------- CAFÉS DISPONIBLES ----------
                const SizedBox(height: 24),
                _seccion('Cafés disponibles (${lotes.length})'),
                if (lotes.isEmpty)
                  const EmptyState(icono: Icons.coffee_outlined, titulo: 'Este vendedor no tiene cafés publicados por ahora')
                else
                  ...lotes.map((lote) => CoffeeLotCard(
                        lote: lote,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotDetailScreen(coffeeLotId: lote.id))),
                      )),
                const SizedBox(height: 90),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (session.usuario != null && !session.esVendedor && lotes.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Solicitar contacto'),
                  onPressed: () {
                    final lote = lotes.firstWhere((l) => l.id == loteDestacadoId, orElse: () => lotes.first);
                    mostrarDialogoInteres(context: context, lote: lote, compradorId: session.usuario!.uid);
                  },
                ),
              ),
            )
          : null,
    );
  }

  Widget _seccion(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

  Widget _datoProductor(IconData icono, String etiqueta, String valor) {
    return SizedBox(
      width: 165,
      child: Row(
        children: [
          Icon(icono, size: 16, color: AppColors.coffeeMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Checklist de confianza — SOLO indicadores respaldados por datos reales
/// del modelo, nunca afirmaciones inventadas (sección 7, 2ª ronda).
class _SeccionConfianza extends StatelessWidget {
  final SellerProfile vendedor;
  final int numLotes;
  const _SeccionConfianza({required this.vendedor, required this.numLotes});

  @override
  Widget build(BuildContext context) {
    final certificacionesLotes = numLotes > 0;
    final indicadores = <String>[
      if (vendedor.verificado) 'Vendedor verificado',
      if (vendedor.departamento.isNotEmpty) 'Información de origen disponible',
      if (vendedor.perfilCompleto) 'Perfil completo',
      if (certificacionesLotes) 'Cafés con información detallada',
      if (vendedor.calificacionPromedio > 0) 'Con calificación de compradores',
    ];

    if (indicadores.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.leafGreenLight.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: indicadores
            .map((texto) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: AppColors.leafGreen),
                      const SizedBox(width: 8),
                      Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5))),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final SellerProfile vendedor;
  final bool tieneGaleria;
  const _Cabecera({required this.vendedor, required this.tieneGaleria});

  @override
  Widget build(BuildContext context) {
    final foto = vendedor.fotoPrincipal;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (foto != null)
          AppImage(path: foto, fit: BoxFit.cover, ampliable: false)
        else
          Container(
            color: AppColors.coffeeDark,
            child: const Center(child: Icon(Icons.agriculture_outlined, color: Colors.white24, size: 72)),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.55)],
            ),
          ),
        ),
        if (tieneGaleria)
          Positioned(
            bottom: 12,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, color: Colors.white, size: 14),
                  SizedBox(width: 5),
                  Text('Ver galería', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
