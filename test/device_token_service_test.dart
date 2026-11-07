import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/device_token_repository.dart';
import 'package:lotea_cafe/services/device_token_service.dart';
import 'package:lotea_cafe/services/push_gateway.dart';

const _tokenA = 'token-fcm-del-dispositivo-a-0123456789';
const _tokenB = 'token-fcm-renovado-del-dispositivo-9876543210';

class _GatewayFalso implements PushGateway {
  PushPermiso permiso;
  PushPermiso permisoTrasPedir;
  String? token;
  bool fallaObtenerToken = false;
  int pedidos = 0;
  int tokensEliminados = 0;
  int _serie = 0;
  final _refresh = StreamController<String>.broadcast();

  _GatewayFalso({this.permiso = PushPermiso.noDeterminado, this.permisoTrasPedir = PushPermiso.concedido, this.token = _tokenA});

  void emitirRenovacion(String nuevo) {
    token = nuevo;
    _refresh.add(nuevo);
  }

  @override
  Future<PushPermiso> estadoPermiso() async => permiso;

  @override
  Future<PushPermiso> pedirPermiso() async {
    pedidos++;
    permiso = permisoTrasPedir;
    return permiso;
  }

  @override
  Future<String?> obtenerToken() async {
    if (fallaObtenerToken) throw StateError('FCM no disponible');
    return token;
  }

  @override
  Future<void> eliminarToken() async {
    tokensEliminados++;
    token = 'token-nuevo-tras-eliminar-${_serie++}-xxxxxxxxxxxx';
  }

  @override
  Stream<String> get tokenRenovado => _refresh.stream;
  @override
  Stream<PushMensaje> get enPrimerPlano => Stream<PushMensaje>.empty();
  @override
  Stream<PushMensaje> get alAbrirNotificacion => Stream<PushMensaje>.empty();
  @override
  Future<PushMensaje?> get mensajeInicial async => null;
}

class _AlmacenFalso implements DeviceTokenStore {
  final Map<String, Map<String, String>> docs = {};
  bool falla = false;

  @override
  Future<void> guardar({required String uid, required String tokenId, required String token, required String plataforma}) async {
    if (falla) throw StateError('sin red');
    docs['$uid/$tokenId'] = {'token': token, 'plataforma': plataforma};
  }

  @override
  Future<void> eliminar({required String uid, required String tokenId}) async {
    if (falla) throw StateError('sin red');
    docs.remove('$uid/$tokenId');
  }

  List<String> tokensDe(String uid) => [for (final e in docs.entries) if (e.key.startsWith('$uid/')) e.value['token']!];
}

DeviceTokenService _servicio(_GatewayFalso g, _AlmacenFalso a) => DeviceTokenService(gateway: g, store: a);

void main() {
  group('identificador del documento', () {
    test('es estable para el mismo token, distinto entre tokens y no contiene el token', () {
      final a1 = DeviceTokenService.idDeToken(_tokenA);
      expect(DeviceTokenService.idDeToken(_tokenA), a1);
      expect(DeviceTokenService.idDeToken(_tokenB), isNot(a1));
      expect(a1.contains(_tokenA), isFalse);
      expect(a1, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });

  group('inicio de sesión y permiso', () {
    test('sin sesión no se guarda nada', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario(null);
      expect(a.docs, isEmpty);
      expect(s.estado, PushEstado.desconocido);
    });

    test('al iniciar sesión SIN permiso NO muestra el diálogo del sistema ni registra', () async {
      final g = _GatewayFalso();
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      expect(g.pedidos, 0);
      expect(a.docs, isEmpty);
      expect(s.estado, PushEstado.desactivadas);
    });

    test('«Activar» pide el permiso y, si se concede, guarda SOLO token y plataforma en la cuenta', () async {
      final g = _GatewayFalso();
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      final estado = await s.activar();
      expect(g.pedidos, 1);
      expect(estado, PushEstado.activas);
      expect(a.docs.keys, ['ana/${DeviceTokenService.idDeToken(_tokenA)}']);
      expect(a.docs.values.single, {'token': _tokenA, 'plataforma': 'android'});
    });

    test('si el usuario rechaza el permiso la app sigue bien: estado «denegadas» y nada guardado', () async {
      final g = _GatewayFalso(permisoTrasPedir: PushPermiso.denegado);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      expect(await s.activar(), PushEstado.denegadas);
      expect(a.docs, isEmpty);
    });

    test('con el permiso YA concedido registra en silencio al iniciar sesión (sin diálogo)', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      expect(g.pedidos, 0);
      expect(s.estado, PushEstado.activas);
      expect(a.tokensDe('ana'), [_tokenA]);
    });

    test('con el permiso revocado en el sistema se borra el registro de este dispositivo', () async {
      final g = _GatewayFalso(permiso: PushPermiso.denegado);
      final a = _AlmacenFalso()..docs['ana/${DeviceTokenService.idDeToken(_tokenA)}'] = {'token': _tokenA, 'plataforma': 'android'};
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      expect(s.estado, PushEstado.denegadas);
      expect(a.docs, isEmpty);
    });

    test('notifica a la interfaz al cambiar de estado', () async {
      final s = _servicio(_GatewayFalso(), _AlmacenFalso());
      var avisos = 0;
      s.addListener(() => avisos++);
      await s.alCambiarUsuario('ana');
      await s.activar();
      expect(avisos, greaterThanOrEqualTo(2));
    });
  });

  group('varios dispositivos y renovación del token', () {
    test('dos dispositivos de la misma cuenta quedan como dos registros distintos', () async {
      final a = _AlmacenFalso();
      final s1 = _servicio(_GatewayFalso(permiso: PushPermiso.concedido, token: _tokenA), a);
      final s2 = _servicio(_GatewayFalso(permiso: PushPermiso.concedido, token: _tokenB), a);
      await s1.alCambiarUsuario('ana');
      await s2.alCambiarUsuario('ana');
      expect(a.tokensDe('ana')..sort(), [_tokenA, _tokenB]..sort());
    });

    test('onTokenRefresh: guarda el token nuevo y borra el anterior (no quedan tokens viejos)', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      g.emitirRenovacion(_tokenB);
      await pumpEventQueue();
      expect(a.tokensDe('ana'), [_tokenB]);
    });

    test('una renovación con el mismo token no duplica ni borra nada', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      g.emitirRenovacion(_tokenA);
      await pumpEventQueue();
      expect(a.tokensDe('ana'), [_tokenA]);
    });

    test('sin sesión no se atienden renovaciones (no se registra token para nadie)', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      await s.liberarDispositivo('ana');
      await s.alCambiarUsuario(null);
      g.emitirRenovacion(_tokenB);
      await pumpEventQueue();
      expect(a.docs, isEmpty);
    });
  });

  group('cerrar sesión y cambio de cuenta', () {
    test('liberarDispositivo borra el registro de la cuenta que sale e invalida el token', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      await s.liberarDispositivo('ana');
      expect(a.docs, isEmpty);
      expect(g.tokensEliminados, 1);
    });

    test('tras cerrar sesión, otra cuenta recibe un token NUEVO y la anterior no conserva nada', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      await s.liberarDispositivo('ana');
      await s.alCambiarUsuario(null);
      await s.alCambiarUsuario('beto');
      expect(a.tokensDe('ana'), isEmpty);
      expect(a.tokensDe('beto'), hasLength(1));
      expect(a.tokensDe('beto').single, isNot(_tokenA));
    });

    test('cambio de cuenta SIN cerrar sesión: se invalida el token anterior y se registra uno nuevo para la nueva', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      await s.alCambiarUsuario('beto');
      expect(g.tokensEliminados, 1);
      expect(a.tokensDe('beto').single, isNot(_tokenA));
    });

    test('liberarDispositivo sin nada registrado no hace nada ni falla', () async {
      final g = _GatewayFalso();
      final s = _servicio(g, _AlmacenFalso());
      await s.alCambiarUsuario('ana');
      await s.liberarDispositivo('ana');
      expect(g.tokensEliminados, 0);
    });
  });

  group('un error de notificaciones nunca se propaga', () {
    test('si Firestore falla al guardar, «Activar» termina en «error» sin lanzar', () async {
      final a = _AlmacenFalso()..falla = true;
      final s = _servicio(_GatewayFalso(), a);
      await s.alCambiarUsuario('ana');
      expect(await s.activar(), PushEstado.error);
    });

    test('si FCM no entrega token, el inicio de sesión sigue y no hay registro', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido)..fallaObtenerToken = true;
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      expect(a.docs, isEmpty);
      expect(s.estado, PushEstado.desactivadas);
    });

    test('liberarDispositivo con Firestore caído no lanza', () async {
      final g = _GatewayFalso(permiso: PushPermiso.concedido);
      final a = _AlmacenFalso();
      final s = _servicio(g, a);
      await s.alCambiarUsuario('ana');
      a.falla = true;
      await s.liberarDispositivo('ana');
    });

    test('«Activar» sin sesión no hace nada', () async {
      final g = _GatewayFalso();
      final s = _servicio(g, _AlmacenFalso());
      expect(await s.activar(), PushEstado.desconocido);
      expect(g.pedidos, 0);
    });
  });

  group('DeviceTokenRepository (Firestore simulado)', () {
    test('guarda exactamente token, plataforma y updatedAt, y permite borrar', () async {
      final db = FakeFirebaseFirestore();
      final repo = DeviceTokenRepository(db: db);
      await repo.guardar(uid: 'ana', tokenId: 'id1', token: _tokenA, plataforma: 'android');
      final doc = await db.collection('users').doc('ana').collection('deviceTokens').doc('id1').get();
      expect(doc.data()!.keys.toSet(), {'token', 'plataforma', 'updatedAt'});
      expect(doc.data()!['token'], _tokenA);
      expect(doc.data()!['plataforma'], 'android');
      expect(doc.data()!['updatedAt'], isA<Timestamp>());
      await repo.eliminar(uid: 'ana', tokenId: 'id1');
      expect((await db.collection('users').doc('ana').collection('deviceTokens').get()).docs, isEmpty);
    });
  });
}
