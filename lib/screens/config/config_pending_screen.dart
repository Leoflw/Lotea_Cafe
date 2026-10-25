import 'package:flutter/material.dart';
import '../../services/firebase_bootstrap.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';

/// Se muestra cuando Firebase no pudo inicializarse. Explica el paso
/// pendiente; no ofrece acceso demo ni oculta el problema.
class ConfigPendingScreen extends StatelessWidget {
  final FirebaseInitResult resultado;
  final VoidCallback onReintentar;

  const ConfigPendingScreen({super.key, required this.resultado, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    final pendiente = resultado.status == FirebaseInitStatus.configuracionPendiente;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 24),
            const LoteaBrandHeader(symbolHeight: 64, nameSize: 32),
            const SizedBox(height: 28),
            Icon(pendiente ? Icons.settings_suggest_outlined : Icons.cloud_off_outlined,
                size: 48, color: AppColors.coffeeMedium),
            const SizedBox(height: 14),
            Text(
              pendiente ? 'Falta conectar Firebase' : 'No se pudo conectar con Firebase',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              pendiente
                  ? 'Esta copia de Lotea Café todavía no está vinculada a un proyecto de Firebase, '
                      'así que no puede iniciar sesión ni leer datos.'
                  : 'Firebase está configurado, pero la inicialización falló. Revisa tu conexión y vuelve a intentarlo.',
              style: const TextStyle(height: 1.4),
            ),
            if (pendiente) ...[
              const SizedBox(height: 18),
              const Text('Pasos pendientes', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                '1. Crear o elegir un proyecto en Firebase Console.\n'
                '2. Generar la carpeta android/ y confirmar el identificador de paquete.\n'
                '3. Ejecutar «flutterfire configure».\n'
                '4. Activar Email/Password y crear Firestore.\n'
                '5. Publicar firestore.rules e índices.\n\n'
                'El detalle exacto está en FIREBASE_SETUP.md.',
                style: TextStyle(height: 1.5),
              ),
            ],
            if (resultado.detalle != null) ...[
              const SizedBox(height: 18),
              Text('Detalle técnico: ${resultado.detalle}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
