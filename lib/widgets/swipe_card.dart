import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/mock_store.dart';
import '../models/coffee_lot.dart';
import '../models/seller_profile.dart';
import '../services/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'app_image.dart';
import 'badges.dart';

/// Tarjeta de descubrimiento: funciona como VISTA PREVIA de un lote de café.
/// Tocarla (o el botón "Ver perfil") abre el detalle completo del vendedor
/// — nunca dispara "Me interesa" por sí sola. Comparte identidad visual
/// con [CoffeeLotCard] (sección 12, 2ª ronda).
class SwipeCard extends StatelessWidget {
  final CoffeeLot lote;
  final SellerProfile? vendedor;
  final VoidCallback onVerPerfil;

  const SwipeCard({
    super.key,
    required this.lote,
    required this.vendedor,
    required this.onVerPerfil,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionProvider>();
    final destacado = session.usuario != null &&
        context.read<MockStore>().coincideConPreferencias(lote, session.usuario!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            path: lote.fotos.isEmpty ? null : lote.fotos.first,
            fit: BoxFit.cover,
            ampliable: false,
          ),

          if (vendedor?.verificado == true)
            const Positioned(top: 16, left: 16, child: VerifiedBadge()),

            if (destacado)
              Positioned(
                top: vendedor?.verificado == true ? 52 : 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.leafGreen, borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('Para ti', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(20)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swipe, color: Colors.white70, size: 13),
                    SizedBox(width: 4),
                    Text('Desliza para explorar', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                  ],
                ),
              ),
            ),

          GestureDetector(
            onTap: onVerPerfil,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lote.nombre,
                              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          RatingBadge(calificacion: vendedor?.calificacionPromedio ?? 0),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        vendedor != null ? '${vendedor!.nombreMarca} · ${vendedor!.ubicacionCorta}' : lote.varietyPrincipal,
                        style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(lote.varietyPrincipal),
                          _chip(lote.proceso),
                          if (lote.altitudMsnm != null) _chip('${lote.altitudMsnm!.toStringAsFixed(0)} msnm'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatCOPPorUnidad(lote.precioCOP, lote.unidad),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                            ),
                          ),
                          AvailabilityChip(disponible: lote.disponible),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onVerPerfil,
                          icon: const Icon(Icons.storefront_outlined, size: 18),
                          label: const Text('VER PERFIL'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.coffeeDark,
                            minimumSize: const Size.fromHeight(42),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
