import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_token_service.dart';
import '../theme/app_theme.dart';

/// Opción discreta de «Mi cuenta» para activar las notificaciones. Es el ÚNICO lugar
/// de la app que puede mostrar el diálogo de permiso del sistema (Android 13+).
class PushActivationCard extends StatelessWidget {
  const PushActivationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final servicio = context.watch<DeviceTokenService>();
    final estado = servicio.estado;
    final gris = TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4);

    final Widget cuerpo;
    switch (estado) {
      case PushEstado.activas:
        cuerpo = Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.leafGreen, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Activadas en este dispositivo. Puedes desactivarlas cuando quieras en los ajustes del teléfono.',
                style: gris,
              ),
            ),
          ],
        );
      case PushEstado.denegadas:
        cuerpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Las notificaciones están desactivadas en el teléfono. Puedes activarlas en Ajustes → Aplicaciones → Lotea Café → Notificaciones.',
              style: gris,
            ),
            const SizedBox(height: 8),
            _boton(servicio, 'Volver a intentarlo'),
          ],
        );
      case PushEstado.error:
        cuerpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No se pudieron activar ahora. Revisa tu conexión e inténtalo de nuevo.', style: gris),
            const SizedBox(height: 8),
            _boton(servicio, 'Activar notificaciones'),
          ],
        );
      case PushEstado.desconocido:
      case PushEstado.desactivadas:
        cuerpo = _boton(servicio, 'Activar notificaciones');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_outlined, color: AppColors.coffeeMedium, size: 20),
                SizedBox(width: 8),
                Text('Notificaciones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Recibe avisos de mensajes y novedades de cotizaciones cuando Lotea Café no está abierta.',
              style: gris,
            ),
            const SizedBox(height: 10),
            cuerpo,
          ],
        ),
      ),
    );
  }

  Widget _boton(DeviceTokenService servicio, String texto) {
    return OutlinedButton.icon(
      onPressed: servicio.trabajando ? null : () => servicio.activar(),
      icon: servicio.trabajando
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.notifications_active_outlined, size: 18),
      label: Text(texto),
    );
  }
}
