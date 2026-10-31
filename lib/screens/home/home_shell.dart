import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/home_tab_notifier.dart';
import '../../state/activity_provider.dart';
import '../../state/session_provider.dart';
import '../discover/discover_screen.dart';
import '../requests/my_requests_screen.dart';
import '../requests/received_requests_screen.dart';
import '../saved/saved_screen.dart';
import '../seller/my_coffee_lots_screen.dart';
import '../profile/my_profile_screen.dart';

/// Contenedor con navegación inferior (el comprador y el vendedor ven
/// pestañas distintas):
///   Comprador: Descubrir · Solicitudes · Guardados · Cuenta
///   Vendedor:  Mi catálogo · Solicitudes · Cuenta
/// Las cotizaciones viven dentro de «Solicitudes» (pestaña propia) para no
/// saturar la barra inferior.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final esVendedor = context.select<SessionProvider, bool>((s) => s.esVendedor);
    final tabs = context.watch<HomeTabNotifier>();
    final actividad = context.watch<ActivityProvider>();

    // Cada elemento se cuenta una sola vez: solicitudes por responder,
    // cotizaciones que esperan una acción de esta persona y conversaciones con
    // mensajes sin leer (una conversación = 1, tenga los mensajes que tenga).
    final accionesPendientes = (esVendedor
            ? actividad.pendientes.length + actividad.cotizacionesPorResponder
            : actividad.ofertasPorResponder) +
        actividad.chatsConNoLeidos;

    final paginas = esVendedor
        ? const [MyCoffeeLotsScreen(), ReceivedRequestsScreen(), MyProfileScreen()]
        : const [DiscoverScreen(), MyRequestsScreen(), SavedScreen(), MyProfileScreen()];

    BottomNavigationBarItem solicitudes(IconData i, IconData ia) => BottomNavigationBarItem(
          icon: Badge(isLabelVisible: accionesPendientes > 0, label: Text('$accionesPendientes'), child: Icon(i)),
          activeIcon: Badge(isLabelVisible: accionesPendientes > 0, label: Text('$accionesPendientes'), child: Icon(ia)),
          label: 'Solicitudes',
        );

    final items = esVendedor
        ? [
            const BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Mi catálogo'),
            solicitudes(Icons.inbox_outlined, Icons.inbox),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Cuenta'),
          ]
        : [
            const BottomNavigationBarItem(icon: Icon(Icons.travel_explore_outlined), activeIcon: Icon(Icons.travel_explore), label: 'Descubrir'),
            solicitudes(Icons.outbox_outlined, Icons.outbox),
            const BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), activeIcon: Icon(Icons.bookmark), label: 'Guardados'),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Cuenta'),
          ];

    final indice = tabs.indice >= paginas.length ? 0 : tabs.indice;

    return Scaffold(
      body: IndexedStack(index: indice, children: paginas),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: indice,
        onTap: tabs.ir,
        items: items,
      ),
    );
  }
}
