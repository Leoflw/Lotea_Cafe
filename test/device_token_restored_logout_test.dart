import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/services/device_token_service.dart';
import 'package:lotea_cafe/services/push_gateway.dart';

const _token = 'token-fcm-del-dispositivo-a-0123456789';

class _Gateway implements PushGateway {
  bool fallaObtener = false;
  int eliminados = 0;

  @override
  Future<PushPermiso> estadoPermiso() async => PushPermiso.concedido;
  @override
  Future<PushPermiso> pedirPermiso() async => PushPermiso.concedido;
  @override
  Future<String?> obtenerToken() async {
    if (fallaObtener) throw StateError('FCM no disponible');
    return _token;
  }

  @override
  Future<void> eliminarToken() async => eliminados++;
  @override
  Stream<String> get tokenRenovado => Stream<String>.empty();
  @override
  Stream<PushMensaje> get enPrimerPlano => Stream<PushMensaje>.empty();
  @override
  Stream<PushMensaje> get alAbrirNotificacion => Stream<PushMensaje>.empty();
  @override
  Future<PushMensaje?> get mensajeInicial async => null;
}

class _Almacen implements DeviceTokenStore {
  final docs = <String>{};
  bool falla = false;

  @override
  Future<void> guardar({required String uid, required String tokenId, required String token, required String plataforma}) async {
    docs.add('$uid/$tokenId');
  }

  @override
  Future<void> eliminar({required String uid, required String tokenId}) async {
    if (falla) throw StateError('sin red');
    docs.remove('$uid/$tokenId');
  }
}

void main() {
  test('sesión restaurada en arranque en frío: borra el registro de ESTE dispositivo aunque la memoria esté vacía', () async {
    final g = _Gateway();
    final a = _Almacen();
    final s = DeviceTokenService(gateway: g, store: a);
    // Registro dejado por la ejecución anterior de la app; este proceso nunca llamó a alCambiarUsuario.
    a.docs.add('ana/${DeviceTokenService.idDeToken(_token)}');
    a.docs.add('ana/otro-dispositivo');

    await s.liberarDispositivoDeSesionRestaurada('ana');

    expect(a.docs, {'ana/otro-dispositivo'}, reason: 'solo se borra el de este dispositivo');
    expect(g.eliminados, 1, reason: 'el token de FCM se invalida');
    s.dispose();
  });

  test('si no se puede obtener el token no lanza y aun así intenta invalidarlo', () async {
    final g = _Gateway()..fallaObtener = true;
    final s = DeviceTokenService(gateway: g, store: _Almacen());
    await s.liberarDispositivoDeSesionRestaurada('ana');
    expect(g.eliminados, 1);
    s.dispose();
  });

  test('si Firestore falla no lanza', () async {
    final g = _Gateway();
    final a = _Almacen()..falla = true;
    final s = DeviceTokenService(gateway: g, store: a);
    await s.liberarDispositivoDeSesionRestaurada('ana');
    expect(g.eliminados, 1);
    s.dispose();
  });
}
