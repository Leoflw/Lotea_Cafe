import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/push_config.dart';
import 'package:lotea_cafe/services/push_notifier.dart';

const _config = PushConfig(endpoint: 'https://push.example.workers.dev/');

class _Prueba {
  final List<http.Request> peticiones = [];
  final List<Duration> esperas = [];
  late final PushNotificationClient cliente;

  _Prueba(http.Response Function(int intento) responder, {PushConfig config = _config, String? idToken = 'id-token-falso'}) {
    cliente = PushNotificationClient(
      config: config,
      cliente: MockClient((r) async {
        peticiones.add(r);
        return responder(peticiones.length);
      }),
      obtenerIdToken: () async => idToken,
      dormir: (d) async => esperas.add(d),
    );
  }
}

void main() {
  group('PushConfig', () {
    test('solo se considera configurado con una URL HTTPS', () {
      expect(const PushConfig().configurado, isFalse);
      expect(const PushConfig(endpoint: 'http://x.example.com').configurado, isFalse);
      expect(const PushConfig(endpoint: 'https://x.example.com').configurado, isTrue);
    });

    test('notifyUri añade /notify sin duplicar barras', () {
      expect(const PushConfig(endpoint: 'https://x.example.com/').notifyUri.toString(), 'https://x.example.com/notify');
      expect(const PushConfig(endpoint: 'https://x.example.com').notifyUri.toString(), 'https://x.example.com/notify');
    });
  });

  group('PushNotificationClient', () {
    test('un mensaje envía SOLO el tipo y los dos identificadores, con el token de sesión', () async {
      final p = _Prueba((_) => http.Response('{}', 200));
      await p.cliente.mensajeEnviado(conexionId: 'buyer1_lot1', mensajeId: 'msg-1');
      expect(p.peticiones, hasLength(1));
      final r = p.peticiones.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://push.example.workers.dev/notify');
      expect(r.headers['Authorization'], 'Bearer id-token-falso');
      expect(jsonDecode(r.body), {'tipo': 'chatMessage', 'connectionId': 'buyer1_lot1', 'messageId': 'msg-1'});
    });

    test('una cotización envía SOLO el tipo, el id de la cotización y el del evento', () async {
      final p = _Prueba((_) => http.Response('{}', 200));
      await p.cliente.eventoDeCotizacion(quoteId: 'q1', eventoId: 'ev1');
      final cuerpo = jsonDecode(p.peticiones.single.body) as Map<String, dynamic>;
      expect(cuerpo, {'tipo': 'quoteEvent', 'quoteId': 'q1', 'eventId': 'ev1'});
    });

    test('el cuerpo NUNCA lleva destinatario, token FCM, texto ni ruta', () async {
      final p = _Prueba((_) => http.Response('{}', 200));
      await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      await p.cliente.eventoDeCotizacion(quoteId: 'q', eventoId: 'e');
      const prohibidos = ['uid', 'recipient', 'destinatario', 'token', 'title', 'body', 'path', 'ruta', 'texto'];
      for (final r in p.peticiones) {
        final claves = (jsonDecode(r.body) as Map<String, dynamic>).keys.map((k) => k.toLowerCase());
        for (final c in claves) {
          expect(prohibidos.any(c.contains), isFalse, reason: 'clave no permitida: $c');
        }
      }
    });

    test('sin URL del Worker configurada no hace ninguna petición ni falla', () async {
      final p = _Prueba((_) => http.Response('{}', 200), config: const PushConfig());
      await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      expect(p.peticiones, isEmpty);
    });

    test('sin sesión (sin token) no hace ninguna petición', () async {
      final p = _Prueba((_) => http.Response('{}', 200), idToken: null);
      await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      expect(p.peticiones, isEmpty);
    });

    test('503 y luego 200: reintenta UNA vez tras esperar', () async {
      final p = _Prueba((n) => http.Response('{}', n == 1 ? 503 : 200));
      await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      expect(p.peticiones, hasLength(2));
      expect(p.esperas, hasLength(1));
    });

    test('si el segundo intento también falla no lanza y no hay un tercero', () async {
      final p = _Prueba((_) => http.Response('{}', 503));
      await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      expect(p.peticiones, hasLength(2));
    });

    test('errores del cliente (4xx) y respuestas definitivas no se reintentan', () async {
      for (final codigo in [400, 401, 403, 404, 409, 413, 202, 200]) {
        final p = _Prueba((_) => http.Response('{}', codigo));
        await p.cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
        expect(p.peticiones, hasLength(1), reason: 'código $codigo');
      }
    });

    test('un fallo de red se reintenta una vez y nunca llega al llamador', () async {
      var llamadas = 0;
      final cliente = PushNotificationClient(
        config: _config,
        cliente: MockClient((_) async {
          llamadas++;
          throw http.ClientException('sin red');
        }),
        obtenerIdToken: () async => 'id-token-falso',
        dormir: (_) async {},
      );
      await cliente.mensajeEnviado(conexionId: 'c', mensajeId: 'm');
      expect(llamadas, 2);
    });

    test('si no se puede obtener el token de sesión no lanza', () async {
      final cliente = PushNotificationClient(
        config: _config,
        cliente: MockClient((_) async => http.Response('{}', 200)),
        obtenerIdToken: () async => throw StateError('sin sesión'),
        dormir: (_) async {},
      );
      await cliente.eventoDeCotizacion(quoteId: 'q', eventoId: 'e');
    });
  });

  group('avisarSinEsperar', () {
    test('un error del aviso se traga: no llega a la operación comercial', () async {
      avisarSinEsperar(() async => throw StateError('el Worker falló'));
      avisarSinEsperar(() => Future<void>.error(Exception('otro')));
      await Future<void>.delayed(Duration.zero); // si el error escapara, flutter_test fallaría la prueba
    });

    test('no espera al aviso: devuelve el control de inmediato', () async {
      var terminado = false;
      avisarSinEsperar(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        terminado = true;
      });
      expect(terminado, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(terminado, isTrue);
    });
  });
}
