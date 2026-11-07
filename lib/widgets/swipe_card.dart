import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/coffee_lot.dart';
import '../state/session_provider.dart';
import '../utils/catalog_logic.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';
import 'badges.dart';
import 'price_text.dart';

/// Tarjeta de descubrimiento (vista previa de un lote).
///
/// Composición: la FOTOGRAFÍA es la protagonista (~56 % de la altura) y el
/// PRECIO va sobre ella, en una etiqueta blanca sólida (legible con cualquier
/// foto, sin degradados). Debajo, un panel con el nombre en tipografía serif,
/// el productor, tres etiquetas (origen, variedad, proceso), una franja de
/// datos clave (solo los que el lote realmente tiene) y el botón. El panel
/// se adapta a la altura disponible: en teléfonos pequeños prescinde primero
/// de la franja de datos, nunca desborda. Lo demás vive en el detalle.
///
/// Acciones: tocar cualquier parte de la tarjeta abre el perfil y el botón
/// "Ver perfil" es la misma acción hecha visible (no hay más equivalentes).
/// Nunca dispara "Me interesa".
class SwipeCard extends StatelessWidget {
  final CoffeeLot lote;
  final VoidCallback onVerPerfil;

  /// Pista discreta "Desliza"; el padre la oculta tras unas interacciones.
  final bool mostrarPista;

  const SwipeCard({
    super.key,
    required this.lote,
    required this.onVerPerfil,
    this.mostrarPista = false,
  });

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<SessionProvider>().usuario;
    final coincide = usuario != null && CatalogLogic.coincideConPreferencias(lote, usuario);

    return Semantics(
      button: true,
      label: 'Ver perfil de ${lote.sellerNombreMarca.isEmpty ? lote.nombre : lote.sellerNombreMarca}, ${lote.nombre}',
      child: Material(
        color: AppColors.surface,
        elevation: 3,
        shadowColor: AppColors.coffeeDark.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AppRadius.sheet + 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onVerPerfil,
          child: LayoutBuilder(
            builder: (context, c) {
              final compacto = c.maxHeight < 400;
              return Column(
                children: [
                  Expanded(
                    flex: compacto ? 52 : 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AppImage(
                          path: lote.fotoPrincipal,
                          fit: BoxFit.cover,
                          ampliable: false,
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (lote.vendedorVerificado) const VerifiedBadge(compacto: true),
                                    if (coincide) const _EtiquetaPreferencias(),
                                  ],
                                ),
                              ),
                              if (mostrarPista)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.32),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swipe, color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text('Desliza', style: TextStyle(color: Colors.white, fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Precio y disponibilidad sobre la foto, en piezas sólidas.
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(AppRadius.control + 2),
                                  ),
                                  child: PriceText(valor: lote.precioCOP, unidad: lote.unidad, size: 22),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AvailabilityChip(disponible: lote.disponible),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: compacto ? 48 : 44,
                    child: _PanelInfo(lote: lote, compacto: compacto, onVerPerfil: onVerPerfil),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Panel inferior de la tarjeta. Reparte el espacio según la altura real:
/// con altura de sobra añade la franja de datos clave (en lugar de dejar un
/// hueco entre las etiquetas y el botón); con poca altura la omite.
class _PanelInfo extends StatelessWidget {
  final CoffeeLot lote;
  final bool compacto;
  final VoidCallback onVerPerfil;

  const _PanelInfo({required this.lote, required this.compacto, required this.onVerPerfil});

  /// Datos comerciales/técnicos disponibles (máximo 3), sin inventar ninguno.
  List<(String, String)> _datos() {
    final datos = <(String, String)>[
      if (lote.puntajeTaza != null) (lote.puntajeTaza!.toStringAsFixed(1), 'Puntaje'),
      if (lote.altitudMsnm != null) (lote.altitudMsnm!.toStringAsFixed(0), 'msnm'),
      if (lote.pedidoMinimoKg != null) ('${lote.pedidoMinimoKg!.toStringAsFixed(0)} kg', 'Pedido mín.'),
      if (lote.cantidadDisponibleKg != null) ('${lote.cantidadDisponibleKg!.toStringAsFixed(0)} kg', 'Disponible'),
    ];
    return datos.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final origen = lote.departamento;
    final datos = _datos();
    return LayoutBuilder(
      builder: (context, c) {
        final alto = c.maxHeight;
        final vPad = compacto ? 8.0 : 12.0;
        // Alturas mínimas (en px a escala de texto 1.0) con las que cada
        // bloque cabe sin desbordar; crecen con el tamaño de letra del sistema.
        final k = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6).toDouble();
        final base = (compacto ? 131.0 : 143.0) * k;
        final notas = lote.perfilSensorial.notas;
        final mostrarDatos = datos.isNotEmpty && alto >= base + 44 * k;
        final mostrarNotas = !mostrarDatos && notas.isNotEmpty && alto >= base + 24 * k;
        final mostrarEtiquetas = alto >= 112 * k;
        final mostrarProductor = alto >= 96 * k && lote.sellerNombreMarca.isNotEmpty;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, vPad, 16, vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lote.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1.15),
                  ),
                  if (mostrarProductor) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined, size: 14, color: AppColors.inkSoft),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            lote.sellerNombreMarca,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (mostrarEtiquetas) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (origen.isNotEmpty) Flexible(child: AttributeTag(icono: Icons.place_outlined, texto: origen)),
                        if (lote.varietyPrincipal.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(child: AttributeTag(texto: lote.varietyPrincipal)),
                        ],
                        if (lote.proceso.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(child: AttributeTag(texto: lote.proceso)),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
              if (mostrarDatos) _FranjaDatos(datos: datos),
              if (mostrarNotas)
                Text(
                  notas.take(3).join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 15, color: AppColors.coffeeMedium),
                ),
              SizedBox(
                width: double.infinity,
                height: compacto ? 38 : 42,
                child: ElevatedButton.icon(
                  onPressed: onVerPerfil,
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Ver perfil'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Hasta tres cifras clave separadas por líneas finas.
class _FranjaDatos extends StatelessWidget {
  final List<(String, String)> datos;
  const _FranjaDatos({required this.datos});

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    for (var i = 0; i < datos.length; i++) {
      if (i > 0) hijos.add(Container(width: 1, height: 22, color: AppColors.outline));
      hijos.add(
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(datos[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.1)),
              const SizedBox(height: 2),
              Text(datos[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.1)),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(children: hijos),
    );
  }
}

class _EtiquetaPreferencias extends StatelessWidget {
  const _EtiquetaPreferencias();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.leafGreen.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('Coincide con tus preferencias', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
