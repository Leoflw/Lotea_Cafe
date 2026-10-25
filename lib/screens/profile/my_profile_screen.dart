import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';

/// Perfil de cuenta: datos básicos del usuario y cierre de sesión.
/// (Historial de transacciones y calificaciones son el siguiente paso
/// natural a agregar aquí una vez esté el módulo de pagos — sección 2.3).
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final usuario = session.usuario!;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.coffeeLight,
              child: Text(
                usuario.nombre.isNotEmpty ? usuario.nombre[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 32, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(usuario.nombre, style: Theme.of(context).textTheme.titleLarge),
          ),
          Center(
            child: Text(
              usuario.rol.label,
              style: const TextStyle(color: AppColors.leafGreen, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          _Fila(icono: Icons.email_outlined, texto: usuario.email),
          if (usuario.ubicacion != null)
            _Fila(icono: Icons.location_on_outlined, texto: usuario.ubicacion!),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () {
              context.read<SessionProvider>().cerrarSesion();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout, color: AppColors.danger),
            label: const Text('Cerrar sesión', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _Fila({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icono, color: AppColors.coffeeMedium, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
