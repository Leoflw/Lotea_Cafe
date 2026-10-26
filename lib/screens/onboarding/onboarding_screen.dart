import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

/// Pantalla breve tras el registro para que la persona entienda de
/// inmediato para qué sirve la app — lenguaje de marketplace, nunca de
/// citas (sección 28, 2ª ronda). Aclara explícitamente que el swipe es
/// solo una forma más de explorar, no el objetivo de la app.
class OnboardingScreen extends StatelessWidget {
  final UserRole rol;
  const OnboardingScreen({super.key, required this.rol});

  @override
  Widget build(BuildContext context) {
    final esVendedor = rol == UserRole.vendedor;

    final pasos = esVendedor
        ? const [
            ('Crea tu perfil de marca', Icons.storefront_outlined),
            ('Publica uno o varios cafés', Icons.coffee_outlined),
            ('Recibe solicitudes de compradores', Icons.inbox_outlined),
            ('Conecta y cotiza directamente', Icons.handshake_outlined),
          ]
        : const [
            ('Descubre cafés', Icons.travel_explore_outlined),
            ('Conoce productores', Icons.storefront_outlined),
            ('Explora su origen', Icons.location_on_outlined),
            ('Conecta directamente', Icons.handshake_outlined),
            ('Solicita cotizaciones', Icons.request_quote_outlined),
          ];

    return Scaffold(
      backgroundColor: AppColors.coffeeDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(esVendedor ? Icons.storefront_outlined : Icons.travel_explore_outlined, color: Colors.white, size: 52),
              const SizedBox(height: 20),
              Text(
                esVendedor ? 'Publica tus cafés y\nconecta con compradores.' : 'Encuentra cafés y\nproductores según tus necesidades.',
                style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold, height: 1.3),
              ),
              const SizedBox(height: 24),
              ...pasos.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(p.$2, color: Colors.white70, size: 18),
                        const SizedBox(width: 12),
                        Text(p.$1, style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
                      ],
                    ),
                  )),
              if (!esVendedor) ...[
                const SizedBox(height: 8),
                Text(
                  'El swipe es solo una forma rápida de explorar — puedes usar también la lista y los filtros.',
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12.5, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.coffeeDark),
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeShell()),
                    (route) => false,
                  ),
                  child: Text(esVendedor ? 'Crear mi perfil de marca' : 'Empezar a descubrir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
