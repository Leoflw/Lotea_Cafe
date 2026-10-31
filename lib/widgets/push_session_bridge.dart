import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/device_token_service.dart';
import '../services/push_navigation.dart';
import '../state/session_provider.dart';

/// Conecta la sesión con las notificaciones: arranca la escucha de mensajes push y
/// avisa de cada cambio de cuenta al registro de dispositivos y al coordinador de
/// navegación. Se monta una sola vez, sobre el navegador (`MaterialApp.builder`).
class PushSessionBridge extends StatefulWidget {
  final Widget child;
  const PushSessionBridge({super.key, required this.child});

  @override
  State<PushSessionBridge> createState() => _PushSessionBridgeState();
}

class _PushSessionBridgeState extends State<PushSessionBridge> {
  String? _ultimoUid;
  bool _hayUltimo = false;

  @override
  void initState() {
    super.initState();
    // Puede ejecutarse antes de que la sesión esté lista: el coordinador conserva lo pendiente.
    context.read<PushCoordinator>().iniciar();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SessionProvider>();
    final estado = sesion.status;
    final uid = estado == SessionStatus.listo ? sesion.uid : null;
    final lista = sesion.autenticado && (sesion.usuario?.onboardingCompleto ?? false);
    final sinSesion = estado == SessionStatus.sinSesion;

    // Los estados de carga o error del perfil no cambian la cuenta registrada.
    final cuentaDefinida = estado == SessionStatus.listo || sinSesion;
    final coordinador = context.read<PushCoordinator>();
    final tokens = context.read<DeviceTokenService>();
    final cambio = cuentaDefinida && (!_hayUltimo || uid != _ultimoUid);
    if (cuentaDefinida) {
      _hayUltimo = true;
      _ultimoUid = uid;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      coordinador.actualizarSesion(uid: uid, lista: lista, sinSesion: sinSesion);
      if (cambio) tokens.alCambiarUsuario(uid);
    });
    return widget.child;
  }
}
