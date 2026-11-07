import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../models/favorite.dart';
import '../../models/seller_profile.dart';
import '../../repositories/coffee_lot_repository.dart';
import '../../repositories/favorite_repository.dart';
import '../../repositories/seller_repository.dart';
import '../../state/activity_provider.dart';
import '../../state/session_provider.dart';
import '../../widgets/remote_view.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/interest_dialog.dart';
import '../../widgets/price_text.dart';
import '../seller/seller_detail_screen.dart';

/// Ficha comercial de un café/lote. Jerarquía: galería a pantalla ancha con el
/// nombre en tipografía serif → vendedor → etiqueta de precio → ficha técnica
/// → perfil de taza → origen → envío → certificaciones.
class CoffeeLotDetailScreen extends StatelessWidget {
  final String coffeeLotId;
  const CoffeeLotDetailScreen({super.key, required this.coffeeLotId});

  @override
  Widget build(BuildContext context) {
    final lots = context.read<CoffeeLotRepository>();
    return StreamView<CoffeeLot?>(
      crear: () => lots.observar(coffeeLotId),
      builder: (context, lote) {
        if (lote == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icono: Icons.error_outline, titulo: 'Café no encontrado'));
        }
        return _ConVendedor(lote: lote);
      },
    );
  }
}

/// Lee el perfil del vendedor del lote; si falla o no existe, el detalle del
/// café se muestra igual (solo sin la sección de origen).
class _ConVendedor extends StatelessWidget {
  final CoffeeLot lote;
  const _ConVendedor({required this.lote});

  @override
  Widget build(BuildContext context) {
    final sellers = context.read<SellerRepository>();
    return StreamBuilder<SellerProfile?>(
      stream: sellers.observar(lote.sellerId),
      builder: (context, snap) => _Detalle(lote: lote, vendedor: snap.data),
    );
  }
}

class _Detalle extends StatelessWidget {
  final CoffeeLot lote;
  final SellerProfile? vendedor;
  const _Detalle({required this.lote, required this.vendedor});

  @override
  Widget build(BuildContext context) {
    final actividad = context.watch<ActivityProvider>();
    final session = context.read<SessionProvider>();
    final puedeGuardar = session.usuario != null && !session.esVendedor;
    final esGuardado = puedeGuardar && actividad.esFavorito(TipoFavorito.cafe, lote.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _CabeceraGaleria(
            fotos: lote.fotosRemotas,
            nombre: lote.nombre,
            mostrarGuardar: puedeGuardar,
            esGuardado: esGuardado,
            onGuardar: () async {
              try {
                await context.read<FavoriteRepository>().alternar(
                      compradorId: session.usuario!.uid,
                      tipo: TipoFavorito.cafe,
                      refId: lote.id,
                      yaEsFavorito: esGuardado,
                    );
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
          ),
          SliverToBoxAdapter(child: _Contenido(lote: lote, vendedor: vendedor)),
        ],
      ),
      // La barra de acción es parte del Scaffold (no flota sobre la ficha):
      // el contenido termina justo encima y la última sección se ve completa.
      bottomNavigationBar: puedeGuardar
          ? DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.outline)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.handshake_outlined),
                    // FittedBox: en pantallas estrechas o con texto grande la
                    // etiqueta se reduce en lugar de desbordar.
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Solicitar contacto — Me interesa')),
                    onPressed: () => mostrarDialogoInteres(context: context, lote: lote),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// Cabecera plegable: la galería ocupa buena parte de la pantalla y, al
/// desplazar, se reduce a una barra con el nombre del café (que por eso no
/// se repite mientras la foto está visible). Mantiene el deslizamiento entre
/// fotos, el contador, las miniaturas y el visor ampliado (toque en la foto).
class _CabeceraGaleria extends StatefulWidget {
  final List<String> fotos;
  final String nombre;
  final bool mostrarGuardar;
  final bool esGuardado;
  final Future<void> Function() onGuardar;

  const _CabeceraGaleria({
    required this.fotos,
    required this.nombre,
    required this.mostrarGuardar,
    required this.esGuardado,
    required this.onGuardar,
  });

  @override
  State<_CabeceraGaleria> createState() => _CabeceraGaleriaState();
}

class _CabeceraGaleriaState extends State<_CabeceraGaleria> {
  final _controller = PageController();
  int _indice = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fotos = widget.fotos;
    final varias = fotos.length > 1;
    final alto = (MediaQuery.sizeOf(context).height * 0.44).clamp(260.0, 400.0).toDouble();
    final altoMin = kToolbarHeight + MediaQuery.paddingOf(context).top;
    final textTheme = Theme.of(context).textTheme;

    return SliverAppBar(
      pinned: true,
      expandedHeight: alto,
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 60,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: _BotonCircular(icono: Icons.arrow_back, tooltip: 'Volver', onTap: () => Navigator.of(context).maybePop()),
      ),
      actions: [
        if (widget.mostrarGuardar)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _BotonCircular(
              icono: widget.esGuardado ? Icons.bookmark : Icons.bookmark_border,
              tooltip: 'Guardar café',
              onTap: widget.onGuardar,
            ),
          ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, c) {
          // t = 1 con la cabecera completa, 0 cuando quedó plegada.
          final t = ((c.maxHeight - altoMin) / (alto - altoMin)).clamp(0.0, 1.0).toDouble();
          final cubre = (((1 - t) - 0.3) / 0.7).clamp(0.0, 1.0).toDouble();
          final tituloAlfa = (((1 - t) - 0.75) / 0.25).clamp(0.0, 1.0).toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              if (fotos.isEmpty)
                const AppImage(path: null, width: double.infinity)
              else
                PageView.builder(
                  controller: _controller,
                  itemCount: fotos.length,
                  onPageChanged: (i) => setState(() => _indice = i),
                  itemBuilder: (context, i) => AppImage(
                    path: fotos[i],
                    galeria: fotos,
                    indiceEnGaleria: i,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              if (varias)
                Positioned(
                  left: 16,
                  right: 84,
                  bottom: 40,
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: fotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _Miniatura(
                      foto: fotos[i],
                      activa: i == _indice,
                      numero: i + 1,
                      onTap: () => _controller.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    ),
                  ),
                ),
              if (varias)
                Positioned(
                  right: 16,
                  bottom: 52,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                        Text('${_indice + 1} / ${fotos.length}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              // Borde superior redondeado de la ficha, que "monta" sobre la foto.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                ),
              ),
              // Al plegarse la cabecera, un velo crema (barato de pintar) tapa la foto.
              IgnorePointer(child: ColoredBox(color: AppColors.cream.withValues(alpha: cubre))),
              Positioned(
                left: 72,
                right: 72,
                bottom: 0,
                height: kToolbarHeight,
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(fontSize: 19, color: AppColors.coffeeDark.withValues(alpha: tituloAlfa)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Botón redondo blanco sobre la foto (legible con cualquier fotografía).
class _BotonCircular extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;
  const _BotonCircular({required this.icono, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.94),
          shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icono, size: 22, color: AppColors.coffeeDark)),
          ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  final String foto;
  final bool activa;
  final int numero;
  final VoidCallback onTap;
  const _Miniatura({required this.foto, required this.activa, required this.numero, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activa,
      label: 'Ver fotografía $numero',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activa ? Colors.white : Colors.transparent, width: 2.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ampliable: false -> tocar la miniatura cambia de foto; la foto grande abre el visor.
                AppImage(path: foto, width: 52, height: 52, ampliable: false),
                if (!activa) const ColoredBox(color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  final CoffeeLot lote;
  final SellerProfile? vendedor;
  const _Contenido({required this.lote, required this.vendedor});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final v = vendedor;
    final marca = v?.nombreMarca ?? lote.sellerNombreMarca;
    final ubicacion = v?.ubicacionCorta ?? [lote.municipio, lote.departamento].where((e) => e.isNotEmpty).join(', ');
    final verificado = v?.verificado ?? lote.vendedorVerificado;
    final mostrarOrigen = v != null || lote.departamento.isNotEmpty;

    return Container(
      color: AppColors.cream,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- ENCABEZADO ----------
          Row(
            children: [
              AvailabilityChip(disponible: lote.disponible),
              if (lote.tipoCafe != null) ...[
                const SizedBox(width: 8),
                Flexible(child: AttributeTag(texto: lote.tipoCafe!)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(lote.nombre, style: textTheme.headlineSmall?.copyWith(fontSize: 30, height: 1.1)),
          if (marca.isNotEmpty || ubicacion.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TarjetaVendedor(
              marca: marca,
              ubicacion: ubicacion,
              verificado: verificado,
              onTap: v == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: v.id))),
            ),
          ],

          // ---------- PRECIO ----------
          const SizedBox(height: 18),
          _EtiquetaPrecio(lote: lote),

          if (lote.descripcion.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(lote.descripcion, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.coffeeDark)),
          ],

          // ---------- FICHA TÉCNICA ----------
          if (_hayFicha) ...[
            const SizedBox(height: 28),
            _Seccion('Ficha técnica', trailing: lote.puntajeTaza != null ? _PuntajeBadge(puntaje: lote.puntajeTaza!) : null),
            _FichaTecnica(lote: lote),
          ] else if (lote.puntajeTaza != null) ...[
            const SizedBox(height: 28),
            _Seccion('Ficha técnica', trailing: _PuntajeBadge(puntaje: lote.puntajeTaza!)),
          ],

          // ---------- PERFIL DE TAZA ----------
          if (!lote.perfilSensorial.estaVacio) ...[
            const SizedBox(height: 28),
            const _Seccion('Perfil de taza'),
            _PerfilTaza(perfil: lote.perfilSensorial),
          ],

          // ---------- ORIGEN ----------
          if (mostrarOrigen) ...[
            const SizedBox(height: 28),
            const _Seccion('Origen'),
            _TarjetaOrigen(lote: lote, vendedor: v),
          ],

          if (lote.metodosEnvio.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _Seccion('Métodos de envío'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: lote.metodosEnvio.map((m) => AttributeTag(icono: Icons.local_shipping_outlined, texto: m)).toList(),
            ),
          ],

          if (lote.certificaciones.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _Seccion('Certificaciones'),
            Wrap(spacing: 8, runSpacing: 8, children: lote.certificaciones.map((c) => CertificationChip(texto: c)).toList()),
          ],
        ],
      ),
    );
  }

  bool get _hayFicha =>
      lote.variedades.isNotEmpty || lote.proceso.isNotEmpty || lote.altitudMsnm != null || lote.cosecha != null;
}

/// Título de sección en DM Serif Display, con un dato opcional a la derecha.
class _Seccion extends StatelessWidget {
  final String texto;
  final Widget? trailing;
  const _Seccion(this.texto, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TarjetaVendedor extends StatelessWidget {
  final String marca;
  final String ubicacion;
  final bool verificado;
  final VoidCallback? onTap;
  const _TarjetaVendedor({required this.marca, required this.ubicacion, required this.verificado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder, side: const BorderSide(color: AppColors.outline)),
      child: InkWell(
        borderRadius: AppRadius.cardBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.surfaceWarm, shape: BoxShape.circle),
                child: const Icon(Icons.storefront_outlined, size: 20, color: AppColors.coffeeMedium),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (marca.isNotEmpty)
                      Text(marca, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                    if (ubicacion.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 13, color: AppColors.inkSoft),
                          const SizedBox(width: 3),
                          Expanded(child: Text(ubicacion, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                        ],
                      ),
                  ],
                ),
              ),
              if (verificado) ...[
                const SizedBox(width: 8),
                const VerifiedBadge(compacto: true),
              ],
              if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Precio como etiqueta comercial sobre superficie blanca (ya no un bloque
/// marrón que rompe la ficha). Cifra grande + datos de compra en tres columnas.
class _EtiquetaPrecio extends StatelessWidget {
  final CoffeeLot lote;
  const _EtiquetaPrecio({required this.lote});

  @override
  Widget build(BuildContext context) {
    final datos = <(IconData, String, String)>[
      if (lote.pedidoMinimoKg != null) (Icons.shopping_bag_outlined, 'Pedido mínimo', '${lote.pedidoMinimoKg!.toStringAsFixed(0)} kg'),
      if (lote.cantidadDisponibleKg != null) (Icons.inventory_2_outlined, 'Disponible', '${lote.cantidadDisponibleKg!.toStringAsFixed(0)} kg'),
      (Icons.straighten_outlined, 'Presentación', lote.unidad),
    ];
    final columnas = <Widget>[];
    for (var i = 0; i < datos.length; i++) {
      if (i > 0) columnas.add(Container(width: 1, height: 38, color: AppColors.outline));
      columnas.add(
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(datos[i].$1, size: 14, color: AppColors.coffeeMedium),
                    const SizedBox(width: 4),
                    Expanded(child: Text(datos[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(datos[i].$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.15)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Precio por ${lote.unidad}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.inkSoft, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          PriceText(valor: lote.precioCOP, unidad: lote.unidad, size: 34),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: columnas),
        ],
      ),
    );
  }
}

class _PuntajeBadge extends StatelessWidget {
  final double puntaje;
  const _PuntajeBadge({required this.puntaje});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 4),
          Text('${puntaje.toStringAsFixed(1)} pts', style: const TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Datos técnicos en cuadrícula de dos columnas (en vez de una nube de
/// chips). Los valores largos, como varias variedades, ocupan la fila entera.
class _FichaTecnica extends StatelessWidget {
  final CoffeeLot lote;
  const _FichaTecnica({required this.lote});

  @override
  Widget build(BuildContext context) {
    final datos = <(IconData, String, String)>[
      if (lote.variedades.isNotEmpty) (Icons.eco_outlined, 'Variedad', lote.variedades.join(', ')),
      if (lote.proceso.isNotEmpty) (Icons.water_drop_outlined, 'Proceso', lote.proceso),
      if (lote.altitudMsnm != null) (Icons.terrain_outlined, 'Altitud', '${lote.altitudMsnm!.toStringAsFixed(0)} msnm'),
      if (lote.cosecha != null) (Icons.calendar_today_outlined, 'Cosecha', '${lote.cosecha}'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final mitad = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in datos)
              SizedBox(
                width: d.$3.length > 16 ? c.maxWidth : mitad,
                child: _DatoFicha(icono: d.$1, etiqueta: d.$2, valor: d.$3),
              ),
          ],
        );
      },
    );
  }
}

class _DatoFicha extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  const _DatoFicha({required this.icono, required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 15, color: AppColors.coffeeMedium),
              const SizedBox(width: 6),
              Expanded(child: Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Text(valor, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.2)),
        ],
      ),
    );
  }
}

/// Notas de taza como texto editorial (serif, separadas por puntos) y tres
/// medidores de tres niveles para acidez, cuerpo y dulzor. Solo se muestran
/// los valores que el lote trae; el texto es exactamente el recibido.
class _PerfilTaza extends StatelessWidget {
  final TasteProfile perfil;
  const _PerfilTaza({required this.perfil});

  @override
  Widget build(BuildContext context) {
    final notas = perfil.notas;
    final medidores = <(String, String)>[
      if (perfil.acidez != null) ('Acidez', perfil.acidez!),
      if (perfil.cuerpo != null) ('Cuerpo', perfil.cuerpo!),
      if (perfil.dulzor != null) ('Dulzor', perfil.dulzor!),
    ];
    final serif = Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1.3, color: AppColors.coffeeMedium);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notas.isNotEmpty)
          Text.rich(
            TextSpan(
              style: serif,
              children: [
                for (var i = 0; i < notas.length; i++) ...[
                  TextSpan(text: notas[i]),
                  if (i < notas.length - 1) const TextSpan(text: '  ·  ', style: TextStyle(color: AppColors.coffeeLight)),
                ],
              ],
            ),
          ),
        if (notas.isNotEmpty && medidores.isNotEmpty) const SizedBox(height: 16),
        if (medidores.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < medidores.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _Medidor(etiqueta: medidores[i].$1, valor: medidores[i].$2)),
              ],
            ],
          ),
      ],
    );
  }
}

int _nivelSensorial(String valor) {
  switch (valor.trim().toLowerCase()) {
    case 'bajo':
    case 'baja':
    case 'ligero':
      return 1;
    case 'medio':
    case 'media':
      return 2;
    case 'alto':
    case 'alta':
    case 'intenso':
      return 3;
    default:
      return 0;
  }
}

class _Medidor extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Medidor({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    final nivel = _nivelSensorial(valor);
    return Semantics(
      label: '$etiqueta: $valor',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.control + 2),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: i < nivel ? AppColors.coffeeMedium : AppColors.surfaceWarm,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
          ],
        ),
      ),
    );
  }
}

/// Origen leído como una dirección: país → municipio, departamento → finca,
/// con la altitud como dato destacado.
class _TarjetaOrigen extends StatelessWidget {
  final CoffeeLot lote;
  final SellerProfile? vendedor;
  const _TarjetaOrigen({required this.lote, required this.vendedor});

  @override
  Widget build(BuildContext context) {
    final v = vendedor;
    final municipio = (v != null && v.municipio.isNotEmpty) ? v.municipio : lote.municipio;
    final departamento = (v != null && v.departamento.isNotEmpty) ? v.departamento : lote.departamento;
    final lugar = [municipio, departamento].where((e) => e.isNotEmpty).join(', ');
    final finca = v?.fincaPrincipal ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COLOMBIA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.inkSoft)),
          if (lugar.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lugar, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, height: 1.15)),
          ],
          if (finca.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.landscape_outlined, size: 18, color: AppColors.coffeeMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Finca  ', style: TextStyle(color: AppColors.inkSoft)),
                        TextSpan(text: finca, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ],
          if (lote.altitudMsnm != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terrain_outlined, size: 18, color: AppColors.coffeeMedium),
                  const SizedBox(width: 8),
                  Text('${lote.altitudMsnm!.toStringAsFixed(0)} msnm', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                  const SizedBox(width: 6),
                  const Text('de altitud', style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
