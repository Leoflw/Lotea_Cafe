import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/session_provider.dart';
import '../discover/discover_screen.dart';
import '../requests/my_requests_screen.dart';
import '../requests/received_requests_screen.dart';
import '../saved/saved_screen.dart';
import '../seller/my_coffee_lots_screen.dart';
import '../profile/my_profile_screen.dart';

/// Contenedor con navegación inferior — reestructurada para dejar de
/// parecer una app de citas (sección 17 del plan de evolución):
///   Comprador: Descubrir · Solicitudes · Guardados · Cuenta
///   Vendedor:  Mi café · Solicitudes · Cuenta
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final esVendedor = context.watch<SessionProvider>().esVendedor;

    final paginas = esVendedor
        ? const [MyCoffeeLotsScreen(), ReceivedRequestsScreen(), MyProfileScreen()]
        : const [DiscoverScreen(), MyRequestsScreen(), SavedScreen(), MyProfileScreen()];

    final items = esVendedor
        ? const [
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Mi catálogo'),
            BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), activeIcon: Icon(Icons.inbox), label: 'Solicitudes'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Cuenta'),
          ]
        : const [
            BottomNavigationBarItem(icon: Icon(Icons.travel_explore_outlined), activeIcon: Icon(Icons.travel_explore), label: 'Descubrir'),
            BottomNavigationBarItem(icon: Icon(Icons.outbox_outlined), activeIcon: Icon(Icons.outbox), label: 'Solicitudes'),
            BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), activeIcon: Icon(Icons.bookmark), label: 'Guardados'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Cuenta'),
          ];

    if (_index >= paginas.length) _index = 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: paginas),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: items,
      ),
    );
  }
}
