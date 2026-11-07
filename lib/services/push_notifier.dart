import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/push_config.dart';

/// Avisa al servicio de notificaciones de que ocurrió algo que merece una
/// notificación. Se llama SOLO después de que Firestore confirmó la operación.
///
/// Ninguna implementación debe lanzar: un fallo al notificar nunca puede
/// deshacer ni hacer parecer fallida una operación comercial ya guardada.
abstract class NotificadorPush {
  /// Un mensaje nuevo en una conexión aceptada.
  Future<void> mensajeEnviado({required String conexionId, required String mensajeId});

  /// Un evento nuevo del historial de una cotización (`quotes/{id}/events/{id}`).
  Future<void> eventoDeCotizacion({required String quoteId, required String eventoId});
}

/// Cliente HTTP del Worker `cloudflare/push-notifications` (`POST /notify`).
///
/// Solo envía el tipo de evento y los identificadores. NUNCA el UID del
/// destinatario, un token FCM, un texto ni una ruta: el Worker los deduce
/// consultando Firestore (ver cloudflare/push-notifications/README.md).
class PushNotificationClient implements NotificadorPush {
  final PushConfig _config;
  final http.Client _cliente;
  final Future<String?> Function() _obtenerIdToken;
  final Duration _tiempoLimite;
  final Duration _espera;
  final Future<void> Function(Duration) _dormir;

  PushNotificationClient({
    PushConfig config = PushConfig.fromEnvironment,
    http.Client? cliente,
    Future<String?> Function()? obtenerIdToken,
    Duration tiempoLimite = const Duration(seconds: 10),
    Duration espera = const Duration(seconds: 2),
    Future<void> Function(Duration)? dormir,
  })  : _config = config,
        _cliente = cliente ?? http.Client(),
        _obtenerIdToken = obtenerIdToken ?? _idTokenDeFirebase,
        _tiempoLimite = tiempoLimite,
        _espera = espera,
        _dormir = dormir ?? Future<void>.delayed;

  static Future<String?> _idTokenDeFirebase() async => FirebaseAuth.instance.currentUser?.getIdToken();

  @override
  Future<void> mensajeEnviado({required String conexionId, required String mensajeId}) =>
      _enviar({'tipo': 'chatMessage', 'connectionId': conexionId, 'messageId': mensajeId});

  @override
  Future<void> eventoDeCotizacion({required String quoteId, required String eventoId}) =>
      _enviar({'tipo': 'quoteEvent', 'quoteId': quoteId, 'eventId': eventoId});

  /// Hasta dos intentos: el segundo solo si el primero falló por red, 429 o 5xx.
  /// Reintentar es seguro porque el Worker deduplica cada evento en Firestore.
  Future<void> _enviar(Map<String, String> cuerpo) async {
    if (!_config.configurado) return;
    try {
      for (var intento = 0; intento < 2; intento++) {
        final idToken = await _obtenerIdToken();
        if (idToken == null || idToken.isEmpty) return;
        if (!await _intentar(idToken, cuerpo)) return;
        if (intento == 0) await _dormir(_espera);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Aviso push no enviado: ${e.runtimeType}');
    }
  }

  /// `true` si conviene reintentar.
  Future<bool> _intentar(String idToken, Map<String, String> cuerpo) async {
    try {
      final r = await _cliente
          .post(
            _config.notifyUri,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
            body: jsonEncode(cuerpo),
          )
          .timeout(_tiempoLimite);
      return r.statusCode == 429 || r.statusCode >= 500;
    } on Object {
      return true; // sin red, tiempo agotado…
    }
  }
}

/// Ejecuta el aviso sin esperarlo y sin permitir que su error llegue a la operación
/// comercial. Úsalo SOLO después de que la escritura en Firestore terminó bien.
void avisarSinEsperar(Future<void> Function() aviso) {
  unawaited(() async {
    try {
      await aviso();
    } catch (e) {
      if (kDebugMode) debugPrint('Aviso push ignorado: ${e.runtimeType}');
    }
  }());
}
