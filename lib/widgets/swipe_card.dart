import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/coffee_lot.dart';
import '../state/session_provider.dart';
import '../utils/catalog_logic.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'app_image.dart';
import 'badges.dart';

/// Tarjeta de descubrimiento (vista previa de un lote).
///
/// Composición: la FOTOGRAFÍA es la protagonista (~58 % de la altura) y la
/// información va en un panel sólido debajo — sin degradado gigante ni
/// texto sobre la foto. Solo se muestra lo más útil: nombre, productor,
/// origen · variedad · proceso, precio y disponibilidad. El resto vive en el
/// detalle.
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
    final origen = lote.departamento;

    return Semantics(
      button: true,
      label: 'Ver perfil de ${lote.sellerNombreMarca.isEmpty ? lote.nombre : lote.sellerNombreMarca}, ${lote.nombre}',
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onVerPerfil,
          child: LayoutBuilder(
            builder: (context, c) {
              final compacto = c.maxHeight < 400;
              return Column(
                children: [
                  Expanded(
                    flex: compacto ? 52 : 58,
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
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.28), borderRadius: BorderRadius.circular(20)),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swipe, color: Colors.white70, size: 12),
                                      SizedBox(width: 4),
                                      Text('Desliza', style: TextStyle(color: Colors.white70, fontSize: 10)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: compacto ? 48 : 42,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, compacto ? 8 : 12, 16, compacto ? 8 : 12),
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
                                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.coffeeDark),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lote.sellerNombreMarca,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [if (origen.isNotEmpty) origen, lote.varietyPrincipal, lote.proceso].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.coffeeDark),
                                ),
                              ),
                              if (!compacto) AvailabilityChip(disponible: lote.disponible),
                            ],
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
                    ),
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

class _EtiquetaPreferencias extends StatelessWidget {
  const _EtiquetaPreferencias();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.leafGreen.withOpacity(0.92), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('Coincide con tus preferencias', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
