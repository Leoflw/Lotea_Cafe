import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'push_gateway.dart';

/// Dónde se guardan los tokens de dispositivo (Firestore en la app real).
abstract class DeviceTokenStore {
  Future<void> guardar({required String uid, required String tokenId, required String token, required String plataforma});
  Future<void> eliminar({required String uid, required String tokenId});
}

enum PushEstado {
  /// Aún no se sabe (sin sesión o comprobando).
  desconocido,

  /// Notificaciones sin activar en este dispositivo.
  desactivadas,

  /// Permiso concedido y dispositivo registrado.
  activas,

  /// La persona rechazó el permiso del sistema.
  denegadas,

  /// Se intentó activar y no se pudo (sin red, sin token…).
  error,
}

/// Ciclo de vida de las notificaciones push en ESTE dispositivo:
/// permiso, token FCM y su registro en `users/{uid}/deviceTokens/{tokenId}`.
///
/// Reglas de diseño:
///  - Nunca lanza: un problema de notificaciones no puede impedir iniciar
///    sesión, enviar un mensaje ni modificar una cotización.
///  - Nunca muestra el diálogo del sistema por su cuenta: solo [activar] (botón
///    de «Mi cuenta») pide el permiso. Con el permiso ya concedido, registra el
///    dispositivo en silencio al iniciar sesión.
///  - Varios dispositivos por usuario: el id del documento se deriva del token
///    (UUID v5), así es estable para ese token, único y no revela nada.
///  - Al cerrar sesión, [liberarDispositivo] borra el registro de la cuenta
///    ANTES de salir (después las reglas ya no lo permitirían) e invalida el token.
class DeviceTokenService extends ChangeNotifier {
  final PushGateway _gateway;
  final DeviceTokenStore _store;
  final String _plataforma;

  DeviceTokenService({required PushGateway gateway, required DeviceTokenStore store, String plataforma = 'android'})
      : _gateway = gateway,
        _store = store,
        _plataforma = plataforma;

  PushEstado _estado = PushEstado.desconocido;
  bool _trabajando = false;
  String? _uid;
  String? _registrado; // token FCM guardado en Firestore para [_uid]
  StreamSubscription<String>? _renovaciones;
  bool _cerrado = false;

  PushEstado get estado => _estado;
  bool get trabajando => _trabajando;

  /// Token ya registrado para la cuenta actual (solo para pruebas y diagnóstico).
  @visibleForTesting
  String? get tokenRegistrado => _registrado;

  /// Id estable del documento para un token.
  static String idDeToken(String token) => const Uuid().v5(Namespace.url.value, token);

  Future<T?> _seguro<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      if (kDebugMode) debugPrint('Notificaciones: ${e.runtimeType}');
      return null;
    }
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  /// Lo llama el puente de sesión: [uid] es la cuenta lista, o null sin sesión.
  Future<void> alCambiarUsuario(String? uid) async {
    if (uid == _uid) return;
    final anterior = _uid;
    _uid = uid;
    _registrado = null;
    await _renovaciones?.cancel();
    _renovaciones = null;
    if (uid == null) {
      _estado = PushEstado.desconocido;
      _avisar();
      return;
    }
    // Cambio de cuenta SIN pasar por «Cerrar sesión» (p. ej. sesión revocada): ya no se
    // puede borrar el registro de la cuenta anterior (las reglas no lo permiten). Se
    // invalida el token para que ese registro quede muerto y lo limpie el Worker.
    if (anterior != null) await _seguro(_gateway.eliminarToken);
    await _sincronizar(uid);
  }

  /// Comprueba el permiso SIN preguntar y, si ya está concedido, registra el dispositivo.
  Future<void> _sincronizar(String uid) async {
    final permiso = await _seguro(_gateway.estadoPermiso) ?? PushPermiso.noDeterminado;
    if (_uid != uid) return;
    switch (permiso) {
      case PushPermiso.concedido:
        final ok = await _registrar(uid);
        if (_uid != uid) return;
        _estado = ok ? PushEstado.activas : PushEstado.desactivadas;
      case PushPermiso.denegado:
        await _limpiarRegistroDeEsteDispositivo(uid);
        _estado = PushEstado.denegadas;
      case PushPermiso.noDeterminado:
        _estado = PushEstado.desactivadas;
    }
    _avisar();
  }

  /// Obtiene el token, lo guarda y empieza a escuchar sus renovaciones.
  Future<bool> _registrar(String uid) async {
    final token = await _seguro(_gateway.obtenerToken);
    if (_uid != uid || token == null || token.isEmpty) return false;
    final guardado = await _guardarToken(uid, token);
    if (!guardado) return false;
    _renovaciones ??= _gateway.tokenRenovado.listen(
      (nuevo) => unawaited(_alRenovar(nuevo)),
      onError: (Object _) {},
    );
    return true;
  }

  Future<bool> _guardarToken(String uid, String token) async {
    final r = await _seguro(() async {
      await _store.guardar(uid: uid, tokenId: idDeToken(token), token: token, plataforma: _plataforma);
      return true;
    });
    if (r != true) return false;
    if (_uid == uid) _registrado = token;
    return true;
  }

  Future<void> _alRenovar(String nuevo) async {
    final uid = _uid;
    if (uid == null || nuevo.isEmpty) return;
    final viejo = _registrado;
    if (viejo == nuevo) return;
    if (!await _guardarToken(uid, nuevo)) return;
    // Con el nuevo guardado, el registro del token anterior sobra: no se dejan tokens viejos.
    if (viejo != null && _uid == uid) {
      await _seguro(() => _store.eliminar(uid: uid, tokenId: idDeToken(viejo)));
    }
    _avisar();
  }

  /// Sin permiso, un registro de una etapa anterior no tiene sentido: se borra el de este dispositivo.
  Future<void> _limpiarRegistroDeEsteDispositivo(String uid) async {
    final token = await _seguro(_gateway.obtenerToken);
    if (token == null || token.isEmpty || _uid != uid) return;
    await _seguro(() => _store.eliminar(uid: uid, tokenId: idDeToken(token)));
  }

  /// Botón «Activar notificaciones»: único punto que puede mostrar el diálogo del sistema.
  Future<PushEstado> activar() async {
    final uid = _uid;
    if (uid == null || _trabajando) return _estado;
    _trabajando = true;
    _avisar();
    try {
      final permiso = await _seguro(_gateway.pedirPermiso) ?? PushPermiso.noDeterminado;
      if (_uid != uid) return _estado;
      switch (permiso) {
        case PushPermiso.concedido:
          _estado = await _registrar(uid) ? PushEstado.activas : PushEstado.error;
        case PushPermiso.denegado:
          _estado = PushEstado.denegadas;
        case PushPermiso.noDeterminado:
          _estado = PushEstado.desactivadas;
      }
    } finally {
      _trabajando = false;
      _avisar();
    }
    return _estado;
  }

  /// Se llama ANTES de cerrar la sesión de [uid]. Nunca lanza.
  Future<void> liberarDispositivo(String uid) async {
    final token = _registrado;
    await _renovaciones?.cancel();
    _renovaciones = null;
    _registrado = null;
    if (token == null) return;
    await _seguro(() => _store.eliminar(uid: uid, tokenId: idDeToken(token)));
    await _seguro(_gateway.eliminarToken); // el siguiente inicio de sesión recibe un token nuevo
  }

  @override
  void dispose() {
    _cerrado = true;
    _renovaciones?.cancel();
    super.dispose();
  }
}
