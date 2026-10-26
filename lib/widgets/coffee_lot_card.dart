import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/mock_store.dart';
import '../models/coffee_lot.dart';
import '../services/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'app_image.dart';
import 'badges.dart';

/// Tarjeta compacta de un lote de café, usada en el modo Lista de
/// descubrimiento, Guardados y "Mi café". Identidad visual compartida con
/// [SwipeCard]: foto, nombre, vendedor, origen, variedad, proceso, precio,
/// disponibilidad y verificación (sección 12, 2ª ronda). No dispara
/// ninguna acción comercial por sí sola — solo navega al detalle.
class CoffeeLotCard extends StatelessWidget {
  final CoffeeLot lote;
  final VoidCallback onTap;
  final Widget? trailing;

  const CoffeeLotCard({super.key, required this.lote, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final store = context.read<MockStore>();
    final vendedor = store.perfilVendedorPorId(lote.sellerId);
    final session = context.read<SessionProvider>();
    final destacado = session.usuario != null &&
        !session.esVendedor &&
        store.coincideConPreferencias(lote, session.usuario!);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (destacado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 13, color: AppColors.leafGreen),
                      const SizedBox(width: 4),
                      Text('Coincide con tus preferencias',
                          style: const TextStyle(color: AppColors.leafGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppImage(
                    path: lote.fotos.isEmpty ? null : lote.fotos.first,
                    galeria: lote.fotos,
                    width: 84,
                    height: 84,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lote.nombre,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (vendedor?.verificado == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified, size: 15, color: AppColors.leafGreen),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vendedor != null ? '${vendedor.nombreMarca} · ${vendedor.departamento}' : lote.varietyPrincipal,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${lote.proceso} · ${lote.varietyPrincipal}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coffeeDark, fontSize: 13.5),
                            ),
                            const SizedBox(width: 8),
                            AvailabilityChip(disponible: lote.disponible),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
