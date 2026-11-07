import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

/// Insignia de "Vendedor verificado" — solo debe usarse cuando el dato
/// real de verificación es true (sección 20: no fabricar confianza).
///
/// Dos presentaciones según dónde vive:
/// * [compacto] (sobre fotografías y junto a nombres pequeños): píldora
///   blanca con el sello verde, legible sobre cualquier foto.
/// * normal (encabezado del vendedor): píldora verde suave con borde.
class VerifiedBadge extends StatelessWidget {
  final bool compacto;
  const VerifiedBadge({super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 10, vertical: compacto ? 3 : 5),
      decoration: BoxDecoration(
        color: compacto ? Colors.white : AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: compacto ? null : Border.all(color: AppColors.leafGreenLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: AppColors.leafGreen, size: compacto ? 13 : 15),
          const SizedBox(width: 4),
          Text(
            'Verificado',
            style: TextStyle(
              color: AppColors.leafGreen,
              fontSize: compacto ? 11 : 12.5,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Certificación (Orgánico, Fair Trade, etc.). Es un ATRIBUTO del lote, no un
/// estado: por eso es rectangular con borde suave y no una píldora de color.
class CertificationChip extends StatelessWidget {
  final String texto;
  const CertificationChip({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control - 2),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_outlined, size: 15, color: AppColors.leafGreen),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(color: AppColors.coffeeDark, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dato breve de un lote (origen, variedad, proceso). Etiqueta rectangular
/// pequeña, sin color semántico: es información, no un estado.
class AttributeTag extends StatelessWidget {
  final IconData? icono;
  final String texto;
  const AttributeTag({super.key, required this.texto, this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: AppColors.inkSoft),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.coffeeDark, fontSize: 12, fontWeight: FontWeight.w700, height: 1.15),
            ),
          ),
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

/// Estado de disponibilidad de un lote (misma píldora que cotizaciones y
/// solicitudes).
class AvailabilityChip extends StatelessWidget {
  final bool disponible;
  const AvailabilityChip({super.key, required this.disponible});

  @override
  Widget build(BuildContext context) => StatusPill(
        label: disponible ? 'Disponible' : 'Agotado',
        tone: disponible ? StatusTone.success : StatusTone.neutral,
      );
}
