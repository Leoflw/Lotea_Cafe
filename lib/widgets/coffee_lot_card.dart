import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/coffee_lot.dart';
import '../state/session_provider.dart';
import '../utils/catalog_logic.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';
import 'badges.dart';
import 'price_text.dart';

const double _anchoFoto = 112;
const double _altoFoto = 140;

/// Tarjeta de un lote de café, usada en el modo Lista de descubrimiento,
/// búsqueda, Guardados, «Mi café» y el catálogo de un vendedor.
///
/// Composición: la FOTOGRAFÍA ocupa todo el alto de la tarjeta (112 × 140) con
/// la disponibilidad sobre ella; a la derecha, nombre y productor arriba, datos
/// de origen / variedad / proceso como etiquetas y, al pie, el PRECIO grande.
/// Si el lote coincide con las preferencias del comprador, una franja verde
/// suave lo indica arriba. No dispara ninguna acción comercial por sí sola —
/// solo navega al detalle.
class CoffeeLotCard extends StatelessWidget {
  final CoffeeLot lote;
  final VoidCallback onTap;
  final Widget? trailing;

  const CoffeeLotCard({super.key, required this.lote, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();
    final destacado = session.usuario != null &&
        !session.esVendedor &&
        CatalogLogic.coincideConPreferencias(lote, session.usuario!);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (destacado) const _BandaPreferencias(),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FotoLote(lote: lote),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: _altoFoto),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lote.nombre,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (lote.vendedorVerificado)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.verified, size: 16, color: AppColors.leafGreen),
                                    ),
                                ],
                              ),
                              if (lote.sellerNombreMarca.isNotEmpty)
                                Text(
                                  lote.sellerNombreMarca,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (lote.departamento.isNotEmpty)
                                    AttributeTag(icono: Icons.place_outlined, texto: lote.departamento),
                                  if (lote.varietyPrincipal.isNotEmpty) AttributeTag(texto: lote.varietyPrincipal),
                                  if (lote.proceso.isNotEmpty) AttributeTag(texto: lote.proceso),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          PriceText(valor: lote.precioCOP, unidad: lote.unidad, size: 20),
                        ],
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FotoLote extends StatelessWidget {
  final CoffeeLot lote;
  const _FotoLote({required this.lote});

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(AppRadius.card - 2);
    return SizedBox(
      width: _anchoFoto,
      height: _altoFoto,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            path: lote.fotoPrincipal,
            galeria: lote.fotosRemotas,
            width: _anchoFoto,
            height: _altoFoto,
            borderRadius: radio,
            ampliable: false, // el toque de la tarjeta abre el detalle; ahí se amplía la galería
          ),
          // Un lote agotado se atenúa para que no compita con los disponibles.
          if (!lote.disponible)
            DecoratedBox(decoration: BoxDecoration(color: Colors.black26, borderRadius: radio)),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AvailabilityChip(disponible: lote.disponible),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandaPreferencias extends StatelessWidget {
  const _BandaPreferencias();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.successContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: AppColors.leafGreen),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Coincide con tus preferencias',
              style: TextStyle(color: AppColors.leafGreen, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
