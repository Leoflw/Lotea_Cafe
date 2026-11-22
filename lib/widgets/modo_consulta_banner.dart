import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/negociacion_restringida.dart';

/// Aviso de «modo de consulta»: la conversación o la cotización se puede leer, pero por ahora no
/// admite acciones nuevas. Si se da [onReintentar] se ofrece «Volver a intentar» (por si la
/// restricción terminó mientras la pantalla seguía abierta).
class ModoConsultaBanner extends StatelessWidget {
  final String texto;
  final VoidCallback? onReintentar;
  final Key? botonReintentarKey;

  const ModoConsultaBanner({super.key, required this.texto, this.onReintentar, this.botonReintentarKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 20, color: AppColors.coffeeDark),
              const SizedBox(width: 8),
              Text(tituloModoConsulta, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
            ],
          ),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.coffeeDark)),
          if (onReintentar != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: botonReintentarKey,
                onPressed: onReintentar,
                style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                child: const Text('Volver a intentar'),
              ),
            ),
        ],
      ),
    );
  }
}
