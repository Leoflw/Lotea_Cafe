import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../models/seller_profile.dart';
import '../../state/activity_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/avatar_logic.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/avatar_circular.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/price_text.dart';
import '../../widgets/status_pill.dart';
import 'coffee_lot_edit_screen.dart';
import 'seller_profile_edit_screen.dart';

/// Filtros del catálogo del vendedor. Solo reflejan estados que existen de
/// verdad: publicado / borrador ([CoffeeLot.estado]) y agotado
/// (publicado con `disponible == false`).
enum _FiltroCatalogo { todos, publicados, borradores, agotados }

/// "Mi catálogo" del vendedor: identidad de la marca, resumen de actividad y
/// la lista de sus cafés, filtrable por estado. Un vendedor puede tener
/// varios cafés. Tocar un café (o «Editar») abre el formulario de edición.
class MyCoffeeLotsScreen extends StatefulWidget {
  const MyCoffeeLotsScreen({super.key});

  @override
  State<MyCoffeeLotsScreen> createState() => _MyCoffeeLotsScreenState();
}

class _MyCoffeeLotsScreenState extends State<MyCoffeeLotsScreen> {
  _FiltroCatalogo _filtro = _FiltroCatalogo.todos;

  bool _cumple(CoffeeLot l, _FiltroCatalogo f) {
    switch (f) {
      case _FiltroCatalogo.todos:
        return true;
      case _FiltroCatalogo.publicados:
        return l.publicado;
      case _FiltroCatalogo.borradores:
        return !l.publicado;
      case _FiltroCatalogo.agotados:
        return l.publicado && !l.disponible;
    }
  }

  void _nuevoCafe(SellerProfile perfil) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoffeeLotEditScreen(sellerId: perfil.id)));

  void _editarPerfil() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerProfileEditScreen()));

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ActivityProvider>();
    if (a.perfilVendedor.cargando || a.lotesPropios.cargando) {
      return Scaffold(appBar: AppBar(title: const Text('Mi catálogo')), body: const Center(child: CircularProgressIndicator()));
    }
    if (a.perfilVendedor.fallo || a.lotesPropios.fallo) {
      final e = (a.perfilVendedor.error ?? a.lotesPropios.error)!;
      return Scaffold(appBar: AppBar(title: const Text('Mi catálogo')), body: RepoErrorView(error: e, onReintentar: a.reintentar));
    }
    final perfil = a.perfilVendedor.data;
    final lotes = a.listaLotesPropios;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi catálogo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Editar perfil de mi marca',
            onPressed: _editarPerfil,
          ),
        ],
      ),
      body: perfil == null
          ? EmptyState(
              icono: Icons.storefront_outlined,
              titulo: 'Primero completa el perfil de tu marca',
              subtitulo: 'Nombre, finca, ubicación e historia — así los compradores sabrán quién eres.',
              textoAccion: 'Crear perfil de marca',
              onAccion: _editarPerfil,
            )
          : _contenido(context, a, perfil, lotes, textTheme),
    );
  }

  Widget _contenido(BuildContext context, ActivityProvider a, SellerProfile perfil, List<CoffeeLot> lotes, TextTheme textTheme) {
    final filtrados = lotes.where((l) => _cumple(l, _filtro)).toList();
    int cuenta(_FiltroCatalogo f) => lotes.where((l) => _cumple(l, f)).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _EncabezadoMarca(
          perfil: perfil,
          publicados: a.lotesPublicados,
          pendientes: a.pendientes.length,
          conexiones: a.conexiones.length,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Row(
            children: [
              Expanded(child: Text('Mis cafés', style: textTheme.headlineSmall?.copyWith(fontSize: 23))),
              ElevatedButton.icon(
                onPressed: () => _nuevoCafe(perfil),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Nuevo café'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
              ),
            ],
          ),
        ),
        if (lotes.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            // Crece con el tamaño de letra del sistema para no recortar los chips.
            height: 50 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0).toDouble(),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              children: [
                for (final f in _FiltroCatalogo.values) ...[
                  _ChipFiltro(
                    etiqueta: _nombreFiltro(f),
                    cantidad: cuenta(f),
                    activo: _filtro == f,
                    onTap: () => setState(() => _filtro = f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        if (lotes.isEmpty)
          _PrimerCafe(onCrear: () => _nuevoCafe(perfil))
        else if (filtrados.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 16),
            child: Text(
              'No tienes cafés en «${_nombreFiltro(_filtro)}».',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          )
        else
          for (final lote in filtrados) ...[
            _FilaCafe(
              lote: lote,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => CoffeeLotEditScreen(sellerId: perfil.id, loteExistente: lote))),
            ),
            const Divider(indent: 20, endIndent: 20),
          ],
      ],
    );
  }

  String _nombreFiltro(_FiltroCatalogo f) {
    switch (f) {
      case _FiltroCatalogo.todos:
        return 'Todos';
      case _FiltroCatalogo.publicados:
        return 'Publicados';
      case _FiltroCatalogo.borradores:
        return 'Borradores';
      case _FiltroCatalogo.agotados:
        return 'Agotados';
    }
  }
}

/// Identidad de la marca y resumen de actividad, en una sola pieza sin cajas
/// anidadas: avatar, nombre en serif, ubicación y tres cifras.
class _EncabezadoMarca extends StatelessWidget {
  final SellerProfile perfil;
  final int publicados;
  final int pendientes;
  final int conexiones;

  const _EncabezadoMarca({
    required this.perfil,
    required this.publicados,
    required this.pendientes,
    required this.conexiones,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarCircular(
                fotoUrl: AvatarLogic.fotoDeMarca(perfil),
                nombre: perfil.nombreMarca,
                radius: 28,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perfil.nombreMarca,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14, color: AppColors.inkSoft),
                        const SizedBox(width: 3),
                        Expanded(child: Text(perfil.ubicacionCorta, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                  ],
                ),
              ),
              if (perfil.verificado) ...[const SizedBox(width: 8), const VerifiedBadge(compacto: true)],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Row(
              children: [
                Expanded(child: _Cifra(valor: publicados, singular: 'café publicado', plural: 'cafés publicados', icono: Icons.coffee_outlined)),
                Container(width: 1, height: 36, color: AppColors.outline),
                Expanded(child: _Cifra(valor: pendientes, singular: 'solicitud pendiente', plural: 'solicitudes pendientes', icono: Icons.inbox_outlined)),
                Container(width: 1, height: 36, color: AppColors.outline),
                Expanded(child: _Cifra(valor: conexiones, singular: 'conexión', plural: 'conexiones', icono: Icons.handshake_outlined)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  final int valor;
  final String singular;
  final String plural;
  final IconData icono;
  const _Cifra({required this.valor, required this.singular, required this.plural, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 16, color: AppColors.coffeeMedium),
              const SizedBox(width: 5),
              Text('$valor', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.1)),
            ],
          ),
          const SizedBox(height: 2),
          Text(valor == 1 ? singular : plural, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.2)),
        ],
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  final String etiqueta;
  final int cantidad;
  final bool activo;
  final VoidCallback onTap;
  const _ChipFiltro({required this.etiqueta, required this.cantidad, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$etiqueta · $cantidad'),
      selected: activo,
      showCheckmark: false,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.coffeeMedium,
      side: BorderSide(color: activo ? AppColors.coffeeMedium : AppColors.outlineStrong),
      labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark, fontWeight: FontWeight.w700, fontSize: 13),
      onSelected: (_) => onTap(),
    );
  }
}

/// Un café del catálogo como fila plana (sin tarjeta): foto, estado, nombre,
/// precio y la acción de editar. Reúne lo que el vendedor necesita ver de un
/// vistazo sin repetir datos.
class _FilaCafe extends StatelessWidget {
  final CoffeeLot lote;
  final VoidCallback onTap;
  const _FilaCafe({required this.lote, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final agotado = lote.publicado && !lote.disponible;
    final sinFoto = lote.fotoPrincipal == null;
    final detalles = [
      if (lote.pedidoMinimoKg != null) 'Pedido mín. ${lote.pedidoMinimoKg!.toStringAsFixed(0)} kg',
      if (lote.cantidadDisponibleKg != null) 'Disponible ${lote.cantidadDisponibleKg!.toStringAsFixed(0)} kg',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImage(
                  path: lote.fotoPrincipal,
                  galeria: lote.fotosRemotas,
                  width: 88,
                  height: 88,
                  borderRadius: BorderRadius.circular(AppRadius.card - 2),
                  ampliable: false,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusPill(
                            label: lote.publicado ? 'Publicado' : 'Borrador',
                            tone: lote.publicado ? StatusTone.success : StatusTone.warning,
                          ),
                          if (agotado) const StatusPill(label: 'Agotado', tone: StatusTone.neutral),
                          if (sinFoto) const StatusPill(label: 'Sin foto', tone: StatusTone.danger, icon: Icons.image_not_supported_outlined),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(lote.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      PriceText(valor: lote.precioCOP, unidad: lote.unidad, size: 18),
                      if (detalles.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(detalles, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: lote.updatedAt == null
                      ? const SizedBox.shrink()
                      : Text('Actualizado ${formatFecha(lote.updatedAt!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall),
                ),
                TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(lote.publicado ? 'Editar' : 'Completar'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío del catálogo: explica cómo empezar, sin datos de ejemplo.
class _PrimerCafe extends StatelessWidget {
  final VoidCallback onCrear;
  const _PrimerCafe({required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icono: Icons.coffee_outlined,
      titulo: 'Publica tu primer café',
      subtitulo: 'Los compradores encontrarán tus lotes en Descubrir. Así se empieza:',
      acciones: [
        const _Paso(numero: 1, titulo: 'Agrega fotos', detalle: 'La primera será la portada de tu publicación.'),
        const _Paso(numero: 2, titulo: 'Cuenta de qué café se trata', detalle: 'Variedad, proceso y perfil de taza.'),
        const _Paso(numero: 3, titulo: 'Define precio y disponibilidad', detalle: 'En pesos colombianos.'),
        const SizedBox(height: 4),
        Text(
          'Puedes guardar un borrador y publicarlo cuando esté listo.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onCrear,
          icon: const Icon(Icons.add),
          label: const Text('Crear mi primer café'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
        ),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;
  final String detalle;
  const _Paso({required this.numero, required this.titulo, required this.detalle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.coffeeMedium, shape: BoxShape.circle),
            child: Text('$numero', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                Text(detalle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
