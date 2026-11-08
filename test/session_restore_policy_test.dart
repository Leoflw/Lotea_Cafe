import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/auth_repository.dart';
import 'package:lotea_cafe/repositories/user_repository.dart';
import 'package:lotea_cafe/services/session_preference.dart';
import 'package:lotea_cafe/state/session_provider.dart';

class _UsuarioFalso implements User {
  @override
  final String uid;
  _UsuarioFalso(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Cerrar sesión emite `null` como lo hace Firebase.
class _AuthFalso implements AuthRepository {
  final controlador = StreamController<User?>.broadcast();
  final List<String> orden;
  int fallosDeCierre;
  _AuthFalso(this.orden, {this.fallosDeCierre = 0});

  @override
  Stream<User?> get authStateChanges => controlador.stream;

  @override
  Future<void> cerrarSesion() async {
    if (fallosDeCierre > 0) {
      fallosDeCierre--;
      orden.add('signOutFalla');
      throw StateError('no se pudo cerrar');
    }
    orden.add('signOut');
    controlador.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeFirebaseFirestore> _baseConUsuario() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('ana').set({
    'uid': 'ana',
    'email': 'ana@example.com',
    'nombre': 'Ana',
    'rol': 'comprador',
    'onboardingCompleto': true,
  });
  return db;
}

SessionProvider _sesion(
  _AuthFalso auth,
  FakeFirebaseFirestore db,
  List<SessionStatus> estados, {
  PreferenciaSesion? preferencia,
  Future<void> Function(String uid)? restaurada,
}) {
  final s = SessionProvider(
    auth: auth,
    users: UserRepository(db: db),
    preferencia: preferencia,
    antesDeCerrarSesionRestaurada: restaurada,
  );
  s.addListener(() => estados.add(s.status));
  return s;
}

void main() {
  test('preferencia desactivada + sesión restaurada: se limpia el dispositivo, se cierra y NUNCA se llega a «listo»', () async {
    final orden = <String>[];
    final estados = <SessionStatus>[];
    final auth = _AuthFalso(orden);
    final s = _sesion(auth, await _baseConUsuario(), estados,
        preferencia: PreferenciaSesion.enMemoria(mantener: false), restaurada: (uid) async => orden.add('antes:$uid'));
    expect(s.status, SessionStatus.iniciando);

    auth.controlador.add(_UsuarioFalso('ana')); // sesión restaurada por Firebase
    await pumpEventQueue();

    expect(orden, ['antes:ana', 'signOut']);
    expect(estados, [SessionStatus.sinSesion], reason: 'sin cargandoPerfil ni listo: la pantalla principal nunca se construye');
    expect(s.status, SessionStatus.sinSesion);
    expect(s.usuario, isNull);
    expect(s.autenticado, isFalse);
    s.dispose();
  });

  test('mientras se cierra la sesión restaurada el estado sigue siendo «iniciando» (splash)', () async {
    final orden = <String>[];
    final estados = <SessionStatus>[];
    final auth = _AuthFalso(orden);
    final espera = Completer<void>();
    final s = _sesion(auth, await _baseConUsuario(), estados,
        preferencia: PreferenciaSesion.enMemoria(mantener: false), restaurada: (uid) => espera.future);

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();
    expect(s.status, SessionStatus.iniciando);
    expect(estados, isEmpty);
    expect(orden, isEmpty);

    espera.complete();
    await pumpEventQueue();
    expect(orden, ['signOut']);
    expect(s.status, SessionStatus.sinSesion);
    s.dispose();
  });

  test('preferencia desactivada + inicio de sesión de la persona (no restaurado): la sesión funciona y no se cierra', () async {
    final orden = <String>[];
    final estados = <SessionStatus>[];
    final auth = _AuthFalso(orden);
    final s = _sesion(auth, await _baseConUsuario(), estados,
        preferencia: PreferenciaSesion.enMemoria(mantener: false), restaurada: (uid) async => orden.add('antes:$uid'));

    auth.controlador.add(null); // primer evento: no había sesión guardada
    await pumpEventQueue();
    expect(s.status, SessionStatus.sinSesion);

    auth.controlador.add(_UsuarioFalso('ana')); // la persona inicia sesión
    await pumpEventQueue();

    expect(orden, isEmpty);
    expect(s.status, SessionStatus.listo);
    expect(s.autenticado, isTrue);
    s.dispose();
  });

  test('preferencia activada + sesión restaurada: se conserva', () async {
    final orden = <String>[];
    final estados = <SessionStatus>[];
    final auth = _AuthFalso(orden);
    final s = _sesion(auth, await _baseConUsuario(), estados,
        preferencia: PreferenciaSesion.enMemoria(), restaurada: (uid) async => orden.add('antes:$uid'));

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();

    expect(orden, isEmpty);
    expect(s.status, SessionStatus.listo);
    s.dispose();
  });

  test('sin preferencia inyectada (comportamiento anterior): se conserva la sesión restaurada', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = _sesion(auth, await _baseConUsuario(), <SessionStatus>[]);

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();

    expect(orden, isEmpty);
    expect(s.status, SessionStatus.listo);
    s.dispose();
  });

  test('si limpiar el dispositivo falla, la sesión se cierra igualmente', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = _sesion(auth, await _baseConUsuario(), <SessionStatus>[],
        preferencia: PreferenciaSesion.enMemoria(mantener: false), restaurada: (uid) async => throw StateError('sin red'));

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();

    expect(orden, ['signOut']);
    expect(s.status, SessionStatus.sinSesion);
    s.dispose();
  });

  test('si no se puede cerrar la sesión: error con reintento, nunca se entra a la app; el reintento cierra', () async {
    final orden = <String>[];
    final estados = <SessionStatus>[];
    final auth = _AuthFalso(orden, fallosDeCierre: 1);
    final s = _sesion(auth, await _baseConUsuario(), estados, preferencia: PreferenciaSesion.enMemoria(mantener: false));

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();

    expect(orden, ['signOutFalla']);
    expect(s.status, SessionStatus.errorPerfil);
    expect(s.error, isNotNull);
    expect(estados.contains(SessionStatus.listo), isFalse);

    s.reintentarPerfil(); // «Reintentar» reintenta el CIERRE, no abre la app
    await pumpEventQueue();

    expect(orden, ['signOutFalla', 'signOut']);
    expect(s.status, SessionStatus.sinSesion);
    expect(estados.contains(SessionStatus.listo), isFalse);
    s.dispose();
  });

  test('tras un fallo de cierre, «Cerrar sesión» también termina cerrándola', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden, fallosDeCierre: 1);
    final s = _sesion(auth, await _baseConUsuario(), <SessionStatus>[], preferencia: PreferenciaSesion.enMemoria(mantener: false));

    auth.controlador.add(_UsuarioFalso('ana'));
    await pumpEventQueue();
    expect(s.status, SessionStatus.errorPerfil);

    await s.cerrarSesion();
    await pumpEventQueue();

    expect(orden, ['signOutFalla', 'signOut']);
    expect(s.status, SessionStatus.sinSesion);
    s.dispose();
  });
}
