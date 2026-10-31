import 'package:firebase_messaging/firebase_messaging.dart';

enum PushPermiso { noDeterminado, concedido, denegado }

/// Lo mínimo que la app necesita de un mensaje push. Los textos NO se leen del
/// mensaje: la app muestra sus propios textos genéricos según la [ruta].
class PushMensaje {
  final String? id;

  /// 'chat' o 'cotizacion' (la define el Worker).
  final String? ruta;

  /// Id de la conexión (chat) o de la cotización.
  final String? destinoId;

  const PushMensaje({this.id, this.ruta, this.destinoId});

  factory PushMensaje.desdeRemoto(RemoteMessage m) => PushMensaje(
        id: m.messageId,
        ruta: m.data['ruta']?.toString(),
        destinoId: m.data['id']?.toString(),
      );
}

/// Frontera con `firebase_messaging`. Existe para poder probar el ciclo de vida
/// de los tokens y la navegación con un doble, sin Firebase ni cuentas reales.
abstract class PushGateway {
  /// Estado del permiso SIN mostrar ningún diálogo.
  Future<PushPermiso> estadoPermiso();

  /// Muestra el diálogo del sistema si procede (Android 13+).
  Future<PushPermiso> pedirPermiso();

  Future<String?> obtenerToken();

  /// Invalida el token en FCM: el siguiente `obtenerToken` generará otro.
  Future<void> eliminarToken();

  Stream<String> get tokenRenovado;
  Stream<PushMensaje> get enPrimerPlano;
  Stream<PushMensaje> get alAbrirNotificacion;
  Future<PushMensaje?> get mensajeInicial;
}

class FirebasePushGateway implements PushGateway {
  final FirebaseMessaging _m;
  FirebasePushGateway({FirebaseMessaging? messaging}) : _m = messaging ?? FirebaseMessaging.instance;

  static PushPermiso _mapa(AuthorizationStatus s) {
    switch (s) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return PushPermiso.concedido;
      case AuthorizationStatus.denied:
        return PushPermiso.denegado;
      case AuthorizationStatus.notDetermined:
        return PushPermiso.noDeterminado;
    }
  }

  @override
  Future<PushPermiso> estadoPermiso() async => _mapa((await _m.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermiso> pedirPermiso() async =>
      _mapa((await _m.requestPermission(alert: true, badge: true, sound: true)).authorizationStatus);

  @override
  Future<String?> obtenerToken() => _m.getToken();

  @override
  Future<void> eliminarToken() => _m.deleteToken();

  @override
  Stream<String> get tokenRenovado => _m.onTokenRefresh;

  @override
  Stream<PushMensaje> get enPrimerPlano => FirebaseMessaging.onMessage.map(PushMensaje.desdeRemoto);

  @override
  Stream<PushMensaje> get alAbrirNotificacion => FirebaseMessaging.onMessageOpenedApp.map(PushMensaje.desdeRemoto);

  @override
  Future<PushMensaje?> get mensajeInicial async {
    final m = await _m.getInitialMessage();
    return m == null ? null : PushMensaje.desdeRemoto(m);
  }
}
