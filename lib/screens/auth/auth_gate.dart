import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/home_tab_notifier.dart';
import '../../services/navigation.dart';
import '../../state/session_provider.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/empty_state.dart';
import '../home/home_shell.dart';
import '../onboarding/onboarding_screen.dart';
import 'complete_profile_screen.dart';
import 'login_screen.dart';

/// Decide qué pantalla ver según el estado de Firebase Authentication y del
/// documento `users/{uid}`. No muestra el login mientras se restaura una
/// sesión válida.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  SessionStatus? _anterior;

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SessionProvider>();
    final estado = sesion.status;

    // Al perder la sesión se vuelve a la raíz (cierra pantallas abiertas) y
    // se reinicia la pestaña: no queda rastro del usuario anterior.
    if (_anterior != null && _anterior != SessionStatus.sinSesion && estado == SessionStatus.sinSesion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
        if (mounted) context.read<HomeTabNotifier>().reiniciar();
      });
    }
    _anterior = estado;

    switch (estado) {
      case SessionStatus.iniciando:
        return const BrandSplash();
      case SessionStatus.cargandoPerfil:
        return const BrandSplash(mensaje: 'Cargando tu cuenta…');
      case SessionStatus.sinSesion:
        return const LoginScreen();
      case SessionStatus.perfilFaltante:
        return const CompleteProfileScreen();
      case SessionStatus.errorPerfil:
        return Scaffold(
          body: SafeArea(
            child: ErrorState(
              mensaje: sesion.error?.mensaje ?? 'No se pudo cargar tu cuenta.',
              onReintentar: sesion.reintentarPerfil,
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(onPressed: sesion.cerrarSesion, child: const Text('Cerrar sesión')),
            ),
          ),
        );
      case SessionStatus.listo:
        final u = sesion.usuario!;
        return u.onboardingCompleto ? const HomeShell() : OnboardingScreen(rol: u.rol);
    }
  }
}
