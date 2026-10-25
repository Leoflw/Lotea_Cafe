import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_screen.dart';

/// Lista de matches del usuario (comprador o vendedor). Se reconstruye
/// automáticamente porque escucha el MockStore (ChangeNotifier).
class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final store = context.watch<MockStore>();
    final usuario = session.usuario!;

    final matches = store.matchesDelUsuario(usuario.uid, esComprador: !session.esVendedor);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis matches')),
      body: matches.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border, size: 56, color: AppColors.coffeeLight),
                    const SizedBox(height: 16),
                    Text(
                      session.esVendedor
                          ? 'Aún no tienes matches.\nCuando un comprador te dé like, aparecerá aquí.'
                          : 'Aún no tienes matches.\nDesliza a la derecha en un perfil que te guste.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final match = matches[i];
                final otroId = session.esVendedor ? match.compradorId : match.vendedorId;
                final otroUsuario = store.usuarioPorId(otroId);
                final perfil = store.perfilPorId(match.perfilId);
                final nombreMostrado = otroUsuario?.nombre ??
                    (session.esVendedor ? 'Comprador' : 'Vendedor');

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.coffeeLight,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(nombreMostrado),
                  subtitle: Text(perfil != null ? perfil.finca : 'Café'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: match.chatId,
                          otroNombre: nombreMostrado,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
