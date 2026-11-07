import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';

/// Precio de un lote con jerarquía: el valor en grande y la unidad en
/// pequeño. Usa el mismo formato de [formatCOP], solo cambia la presentación.
class PriceText extends StatelessWidget {
  final num valor;
  final String unidad;
  final double size;
  final Color color;

  const PriceText({
    super.key,
    required this.valor,
    required this.unidad,
    this.size = 19,
    this.color = AppColors.coffeeDark,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatCOP(valor),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color, height: 1.1),
          ),
          TextSpan(
            text: ' / $unidad',
            style: TextStyle(
              fontSize: math.max(11.5, size * 0.6),
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
