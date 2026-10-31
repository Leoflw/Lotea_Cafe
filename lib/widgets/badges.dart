import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Insignia de "Vendedor verificado" — solo debe usarse cuando el dato
/// real de verificación es true (sección 20: no fabricar confianza).
class VerifiedBadge extends StatelessWidget {
  final bool compacto;
  const VerifiedBadge({super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 10, vertical: compacto ? 3 : 5),
      decoration: BoxDecoration(
        color: AppColors.leafGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Colors.white, size: compacto ? 12 : 14),
          const SizedBox(width: 4),
          Text(
            'Verificado',
            style: TextStyle(
              color: Colors.white,
              fontSize: compacto ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip visual para una certificación (Orgánico, Fair Trade, etc.).
class CertificationChip extends StatelessWidget {
  final String texto;
  const CertificationChip({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.leafGreenLight.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.leafGreenLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_outlined, size: 14, color: AppColors.leafGreen),
          const SizedBox(width: 4),
          Text(texto, style: const TextStyle(color: AppColors.leafGreen, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Estrella + calificación numérica, reutilizable en tarjetas y perfiles.
class RatingBadge extends StatelessWidget {
  final double calificacion;
  final Color color;
  const RatingBadge({super.key, required this.calificacion, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    if (calificacion <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 16),
        const SizedBox(width: 2),
        Text(calificacion.toStringAsFixed(1), style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

/// Estado de disponibilidad de un lote.
class AvailabilityChip extends StatelessWidget {
  final bool disponible;
  const AvailabilityChip({super.key, required this.disponible});

  @override
  Widget build(BuildContext context) {
    final color = disponible ? AppColors.leafGreen : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        disponible ? 'Disponible' : 'Agotado',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
