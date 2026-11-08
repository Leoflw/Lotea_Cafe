import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_preference.dart';
import '../theme/app_theme.dart';

/// Interruptor «Mantener sesión iniciada» de «Mi cuenta». Cambiarlo no cierra la sesión
/// actual ni toca Firebase: solo guarda la preferencia de ESTE dispositivo.
class KeepSessionTile extends StatelessWidget {
  const KeepSessionTile({super.key});

  @override
  Widget build(BuildContext context) {
    final pref = context.watch<PreferenciaSesion>();
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.lock_outline, color: AppColors.coffeeMedium),
        title: const Text('Mantener sesión iniciada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          pref.mantener
              ? 'Al abrir la app entrarás directo, sin escribir tu contraseña. Desactívalo si compartes este teléfono.'
              : 'Al cerrar y volver a abrir la app tendrás que iniciar sesión. Tu sesión actual sigue abierta hasta entonces. '
                  'Si Android cierra la app para liberar memoria, también tendrás que iniciar sesión.',
          style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.4),
        ),
        value: pref.mantener,
        activeThumbColor: AppColors.coffeeMedium,
        onChanged: (valor) async {
          final messenger = ScaffoldMessenger.of(context);
          final guardado = await pref.cambiar(valor);
          if (!guardado) {
            messenger.showSnackBar(
              const SnackBar(content: Text('No se pudo guardar el cambio. Inténtalo de nuevo.'), backgroundColor: AppColors.danger),
            );
          }
        },
      ),
    );
  }
}
