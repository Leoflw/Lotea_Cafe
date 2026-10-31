import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_header.dart';

/// Pantalla breve tras el registro para que la persona entienda de
/// inmediato para qué sirve la app — lenguaje de marketplace, nunca de
/// citas (sección 28, 2ª ronda). Aclara explícitamente que el swipe es
/// solo una forma más de explorar, no el objetivo de la app.
class OnboardingScreen extends StatefulWidget {
  final UserRole rol;
  const OnboardingScreen({super.key, required this.rol});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _guardando = false;
  String? _error;

  Future<void> _continuar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      // Al guardarse onboardingCompleto, el AuthGate abre la pantalla principal.
      await context.read<SessionProvider>().completarOnboarding();
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rol = widget.rol;
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
        // Se centra con la altura disponible; si no cabe (teléfono bajo,
        // texto grande) el contenido se desplaza en lugar de desbordarse.
        child: LayoutBuilder(
          builder: (context, constraints) {
            const pad = 28.0;
            final h = constraints.maxHeight;
            final gapMarca = (h * 0.05).clamp(20.0, 48.0).toDouble();
            final minAlto = h > pad * 2 ? h - pad * 2 : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minAlto),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bloque de marca centrado, sin recuadro: el símbolo es un PNG
                    // transparente que se apoya directamente sobre el fondo oscuro.
                    const LoteaBrandHeader(dark: true, symbolHeight: 72, nameSize: 34),
                    SizedBox(height: gapMarca),
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
                              Flexible(child: Text(p.$1, style: const TextStyle(color: Colors.white70, fontSize: 14.5))),
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
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.coffeeDark),
                        onPressed: _guardando ? null : _continuar,
                        child: _guardando
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : Text(esVendedor ? 'Entrar a mi catálogo' : 'Empezar a descubrir'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
