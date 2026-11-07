import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'repositories/auth_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/coffee_lot_repository.dart';
import 'repositories/device_token_repository.dart';
import 'repositories/favorite_repository.dart';
import 'repositories/image_repository.dart';
import 'repositories/interest_request_repository.dart';
import 'repositories/quote_repository.dart';
import 'repositories/seller_repository.dart';
import 'repositories/user_repository.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/config/config_pending_screen.dart';
import 'services/firebase_bootstrap.dart';
import 'services/device_token_service.dart';
import 'services/home_tab_notifier.dart';
import 'services/navigation.dart';
import 'services/push_destinos.dart';
import 'services/push_gateway.dart';
import 'services/push_navigation.dart';
import 'services/push_notifier.dart';
import 'state/activity_provider.dart';
import 'state/session_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/push_session_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final resultado = await FirebaseBootstrap.inicializar();
  runApp(LoteaCafeApp(inicial: resultado));
}

/// Raíz de Lotea Café. Si Firebase no está listo muestra la pantalla de
/// configuración pendiente (con reintento); si lo está, monta los
/// repositorios y el control de sesión.
class LoteaCafeApp extends StatefulWidget {
  final FirebaseInitResult inicial;
  const LoteaCafeApp({super.key, required this.inicial});

  @override
  State<LoteaCafeApp> createState() => _LoteaCafeAppState();
}

class _LoteaCafeAppState extends State<LoteaCafeApp> {
  late FirebaseInitResult _resultado = widget.inicial;

  Future<void> _reintentar() async {
    final r = await FirebaseBootstrap.inicializar();
    if (mounted) setState(() => _resultado = r);
  }

  @override
  Widget build(BuildContext context) {
    if (_resultado.status != FirebaseInitStatus.listo) {
      return MaterialApp(
        title: 'Lotea Café',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: ConfigPendingScreen(resultado: _resultado, onReintentar: _reintentar),
      );
    }

    return MultiProvider(
      providers: [
        // Notificaciones push: cliente del Worker (solo envía ids), pasarela de FCM y
        // registro de dispositivos. Van ANTES de los repositorios y de la sesión
        // porque estos los usan.
        Provider<NotificadorPush>(create: (_) => PushNotificationClient()),
        Provider<PushGateway>(create: (_) => FirebasePushGateway()),
        ChangeNotifierProvider(
          create: (c) => DeviceTokenService(gateway: c.read<PushGateway>(), store: DeviceTokenRepository()),
        ),
        Provider(create: (_) => AuthRepository()),
        Provider(create: (_) => UserRepository()),
        Provider(create: (_) => SellerRepository()),
        Provider(create: (_) => CoffeeLotRepository()),
        Provider(create: (_) => InterestRequestRepository()),
        Provider(create: (_) => FavoriteRepository()),
        Provider(create: (c) => ChatRepository(notificador: c.read<NotificadorPush>())),
        Provider(create: (c) => QuoteRepository(notificador: c.read<NotificadorPush>())),
        Provider(create: (_) => ImageRepository()),
        ChangeNotifierProvider(
          create: (c) => SessionProvider(
            auth: c.read<AuthRepository>(),
            users: c.read<UserRepository>(),
            // Borra el dispositivo de la cuenta que sale ANTES de cerrar su sesión.
            antesDeCerrarSesion: (uid) => c.read<DeviceTokenService>().liberarDispositivo(uid),
          ),
        ),
        // Qué hacer al recibir o tocar una notificación (abre ChatScreen / QuoteDetailScreen).
        Provider(
          create: (c) => PushCoordinator(
            gateway: c.read<PushGateway>(),
            resolver: resolverDestinoPush(
              conexiones: c.read<InterestRequestRepository>(),
              cotizaciones: c.read<QuoteRepository>(),
            ),
          ),
          dispose: (_, p) => p.dispose(),
        ),
        ChangeNotifierProxyProvider<SessionProvider, ActivityProvider>(
          create: (c) => ActivityProvider(
            sellers: c.read<SellerRepository>(),
            lots: c.read<CoffeeLotRepository>(),
            requests: c.read<InterestRequestRepository>(),
            favorites: c.read<FavoriteRepository>(),
            quotes: c.read<QuoteRepository>(),
          ),
          update: (c, sesion, previo) => (previo ?? ActivityProvider(
                sellers: c.read<SellerRepository>(),
                lots: c.read<CoffeeLotRepository>(),
                requests: c.read<InterestRequestRepository>(),
                favorites: c.read<FavoriteRepository>(),
                quotes: c.read<QuoteRepository>(),
              ))
            ..actualizarSesion(sesion),
        ),
        ChangeNotifierProvider(create: (_) => HomeTabNotifier()),
      ],
      child: MaterialApp(
        title: 'Lotea Café — Descubre. Compara. Conecta.',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.light(),
        builder: (context, child) => PushSessionBridge(child: child ?? const SizedBox.shrink()),
        home: const AuthGate(),
      ),
    );
  }
}
