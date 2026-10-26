import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/favorite.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/interest_dialog.dart';
import '../seller/seller_detail_screen.dart';

/// Información completa de un café/lote, con jerarquía visual clara
/// (sección 5, 2ª ronda): Presentación → Precio → Características →
/// Perfil sensorial (visual) → Origen → Certificaciones.
class CoffeeLotDetailScreen extends StatelessWidget {
  final String coffeeLotId;
  const CoffeeLotDetailScreen({super.key, required this.coffeeLotId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final session = context.read<SessionProvider>();
    final lote = store.lotePorId(coffeeLotId);

    if (lote == null) {
      return const Scaffold(body: EmptyState(icono: Icons.error_outline, titulo: 'Café no encontrado'));
    }

    final vendedor = store.perfilVendedorPorId(lote.sellerId);
    final esGuardado = session.usuario != null &&
        !session.esVendedor &&
        store.esFavorito(compradorId: session.usuario!.uid, tipo: TipoFavorito.cafe, refId: lote.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(lote.nombre, overflow: TextOverflow.ellipsis),
        actions: [
          if (session.usuario != null && !session.esVendedor)
            IconButton(
              icon: Icon(esGuardado ? Icons.bookmark : Icons.bookmark_border),
              tooltip: 'Guardar café',
              onPressed: () => store.alternarFavorito(compradorId: session.usuario!.uid, tipo: TipoFavorito.cafe, refId: lote.id),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          // ---------- PRESENTACIÓN ----------
          _Galeria(fotos: lote.fotos),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(lote.nombre, style: Theme.of(context).textTheme.headlineSmall)),
                    AvailabilityChip(disponible: lote.disponible),
                  ],
                ),
                const SizedBox(height: 6),
                if (vendedor != null)
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: vendedor.id))),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_outlined, size: 16, color: AppColors.coffeeMedium),
                        const SizedBox(width: 4),
                        Text('${vendedor.nombreMarca} · ${vendedor.ubicacionCorta}',
                            style: const TextStyle(color: AppColors.coffeeMedium, fontWeight: FontWeight.w600)),
                        if (vendedor.verificado) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, size: 15, color: AppColors.leafGreen),
                        ],
                      ],
                    ),
                  ),

                // ---------- PRECIO ----------
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.coffeeDark,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          if (lote.pedidoMinimoKg != null)
                            _datoClaro('Pedido mínimo', '${lote.pedidoMinimoKg!.toStringAsFixed(0)} kg'),
                          if (lote.cantidadDisponibleKg != null)
                            _datoClaro('Disponible', '${lote.cantidadDisponibleKg!.toStringAsFixed(0)} kg'),
                          _datoClaro('Presentación', lote.unidad),
                        ],
                      ),
                    ],
                  ),
                ),

                if (lote.descripcion.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(lote.descripcion, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                ],

                // ---------- CARACTERÍSTICAS ----------
                const SizedBox(height: 24),
                _seccion('Características'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _specChip(Icons.eco_outlined, lote.varietyPrincipal),
                    _specChip(Icons.water_drop_outlined, lote.proceso),
                    if (lote.altitudMsnm != null) _specChip(Icons.terrain_outlined, '${lote.altitudMsnm!.toStringAsFixed(0)} msnm'),
                    if (lote.cosecha != null) _specChip(Icons.calendar_today_outlined, 'Cosecha ${lote.cosecha}'),
                    if (lote.puntajeTaza != null) _specChip(Icons.star_outline, '${lote.puntajeTaza!.toStringAsFixed(1)} pts'),
                    if (lote.tipoCafe != null) _specChip(Icons.category_outlined, lote.tipoCafe!),
                  ],
                ),

                // ---------- PERFIL SENSORIAL ----------
                if (!lote.perfilSensorial.estaVacio) ...[
                  const SizedBox(height: 24),
                  _seccion('Perfil de taza'),
                  if (lote.perfilSensorial.notas.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: lote.perfilSensorial.notas.map((n) => _notaChip(n)).toList(),
                      ),
                    ),
                  if (lote.perfilSensorial.acidez != null) _barraSensorial('Acidez', lote.perfilSensorial.acidez!),
                  if (lote.perfilSensorial.cuerpo != null) _barraSensorial('Cuerpo', lote.perfilSensorial.cuerpo!),
                  if (lote.perfilSensorial.dulzor != null) _barraSensorial('Dulzor', lote.perfilSensorial.dulzor!),
                ],

                // ---------- ORIGEN ----------
                if (vendedor != null) ...[
                  const SizedBox(height: 24),
                  _seccion('Origen'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.coffeeLight),
                    ),
                    child: Column(
                      children: [
                        _filaOrigen(Icons.landscape_outlined, 'Finca', vendedor.fincaPrincipal),
                        if (vendedor.municipio.isNotEmpty) _filaOrigen(Icons.location_city_outlined, 'Municipio', vendedor.municipio),
                        _filaOrigen(Icons.map_outlined, 'Departamento', vendedor.departamento),
                        _filaOrigen(Icons.public_outlined, 'País', 'Colombia'),
                        if (lote.altitudMsnm != null)
                          _filaOrigen(Icons.terrain_outlined, 'Altitud', '${lote.altitudMsnm!.toStringAsFixed(0)} msnm', ultimo: true),
                      ],
                    ),
                  ),
                ],

                if (lote.metodosEnvio.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _seccion('Métodos de envío'),
                  Wrap(spacing: 8, children: lote.metodosEnvio.map((m) => Chip(label: Text(m), backgroundColor: Colors.white)).toList()),
                ],

                if (lote.certificaciones.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _seccion('Certificaciones'),
                  Wrap(spacing: 8, runSpacing: 8, children: lote.certificaciones.map((c) => CertificationChip(texto: c)).toList()),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: (session.usuario != null && !session.esVendedor)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Solicitar contacto — Me interesa'),
                  onPressed: () => mostrarDialogoInteres(context: context, lote: lote, compradorId: session.usuario!.uid),
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

  Widget _datoClaro(String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _specChip(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.coffeeLight)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: AppColors.coffeeMedium),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.coffeeDark)),
        ],
      ),
    );
  }

  Widget _notaChip(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.coffeeLight.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: const TextStyle(fontSize: 12, color: AppColors.coffeeDark)),
      );

  Widget _barraSensorial(String etiqueta, String nivel) {
    final fraccion = nivel == 'Alto' ? 1.0 : (nivel == 'Medio' ? 0.62 : 0.3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: fraccion,
                minHeight: 10,
                backgroundColor: AppColors.coffeeLight.withOpacity(0.35),
                valueColor: const AlwaysStoppedAnimation(AppColors.leafGreen),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 48, child: Text(nivel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _filaOrigen(IconData icono, String etiqueta, String valor, {bool ultimo = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 10),
      child: Row(
        children: [
          Icon(icono, size: 17, color: AppColors.coffeeMedium),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(etiqueta, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
        ],
      ),
    );
  }
}

/// Galería del café (sección 3, 2ª ronda): imagen principal grande, swipe
/// entre fotos, indicador de posición y miniaturas — funciona igual con
/// 1 o con 10 fotos, y abre el visor de pantalla completa al tocar.
class _Galeria extends StatefulWidget {
  final List<String> fotos;
  const _Galeria({required this.fotos});

  @override
  State<_Galeria> createState() => _GaleriaState();
}

class _GaleriaState extends State<_Galeria> {
  final _controller = PageController();
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.fotos.isEmpty) {
      return Container(
        height: 220,
        color: AppColors.coffeeLight,
        child: const Icon(Icons.coffee, size: 56, color: Colors.white),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.fotos.length,
                onPageChanged: (i) => setState(() => _indice = i),
                itemBuilder: (context, i) => AppImage(
                  path: widget.fotos[i],
                  galeria: widget.fotos,
                  indiceEnGaleria: i,
                  width: double.infinity,
                  height: 240,
                  fit: BoxFit.cover,
                ),
              ),
              if (widget.fotos.length > 1)
                Positioned(
                  bottom: 10,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                    child: Text('${_indice + 1} / ${widget.fotos.length}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
        if (widget.fotos.length > 1)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.fotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final activo = i == _indice;
                  return GestureDetector(
                    onTap: () => _controller.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: activo ? AppColors.coffeeMedium : Colors.transparent, width: 2),
                      ),
                      child: AppImage(
                        path: widget.fotos[i],
                        galeria: widget.fotos,
                        indiceEnGaleria: i,
                        width: 56,
                        height: 56,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
