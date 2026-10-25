import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/mock_store.dart';
import 'services/session_provider.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

void main() {
  runApp(const CafeMatchApp());
}

class CafeMatchApp extends StatelessWidget {
  const CafeMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MockStore()),
        ChangeNotifierProxyProvider<MockStore, SessionProvider>(
          create: (context) => SessionProvider(context.read<MockStore>()),
          update: (context, store, previous) => previous ?? SessionProvider(store),
        ),
      ],
      child: MaterialApp(
        title: 'CaféMatch (pruebas)',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const LoginScreen(),
      ),
    );
  }
}
