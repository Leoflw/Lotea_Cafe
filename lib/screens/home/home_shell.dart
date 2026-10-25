import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/session_provider.dart';
import '../swipe/swipe_screen.dart';
import '../matches/matches_screen.dart';
import '../profile/seller_profile_edit_screen.dart';
import '../profile/my_profile_screen.dart';

/// Contenedor con navegación inferior. El comprador ve: Descubrir, Matches,
/// Perfil. El vendedor ve: Mi Perfil (café), Matches, Perfil de cuenta.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final esVendedor = session.esVendedor;

    final paginas = esVendedor
        ? const [
            SellerProfileEditScreen(),
            MatchesScreen(),
            MyProfileScreen(),
          ]
        : const [
            SwipeScreen(),
            MatchesScreen(),
            MyProfileScreen(),
          ];

    final items = esVendedor
        ? const [
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront),
              label: 'Mi café',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border),
              activeIcon: Icon(Icons.favorite),
              label: 'Matches',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Cuenta',
            ),
          ]
        : const [
            BottomNavigationBarItem(
              icon: Icon(Icons.coffee_outlined),
              activeIcon: Icon(Icons.coffee),
              label: 'Descubrir',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_border),
              activeIcon: Icon(Icons.favorite),
              label: 'Matches',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Cuenta',
            ),
          ];

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
