import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/auth_repository.dart';
import 'package:lotea_cafe/repositories/user_repository.dart';
import 'package:lotea_cafe/state/session_provider.dart';

class _UsuarioFalso implements User {
  @override
  final String uid;
  _UsuarioFalso(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthFalso implements AuthRepository {
  final controlador = StreamController<User?>.broadcast();
  final List<String> orden;
  _AuthFalso(this.orden);

  @override
  Stream<User?> get authStateChanges => controlador.stream;

  @override
  Future<void> cerrarSesion() async => orden.add('signOut');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SessionProvider> _sesion(_AuthFalso auth, {Future<void> Function(String uid)? antes}) async {
  final s = SessionProvider(auth: auth, users: UserRepository(db: FakeFirebaseFirestore()), antesDeCerrarSesion: antes);
  auth.controlador.add(_UsuarioFalso('ana'));
  await pumpEventQueue();
  return s;
}

void main() {
  test('el registro de notificaciones de la cuenta se libera ANTES de cerrar la sesión', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = await _sesion(auth, antes: (uid) async => orden.add('antes:$uid'));
    await s.cerrarSesion();
    expect(orden, ['antes:ana', 'signOut']);
    s.dispose();
  });

  test('si liberar el dispositivo falla, la sesión se cierra igualmente', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = await _sesion(auth, antes: (uid) async => throw StateError('sin red'));
    await s.cerrarSesion();
    expect(orden, ['signOut']);
    s.dispose();
  });

  test('sin gancho (como en las pruebas existentes) cerrar sesión funciona igual', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = await _sesion(auth);
    await s.cerrarSesion();
    expect(orden, ['signOut']);
    s.dispose();
  });

  test('sin usuario activo no se invoca el gancho', () async {
    final orden = <String>[];
    final auth = _AuthFalso(orden);
    final s = SessionProvider(auth: auth, users: UserRepository(db: FakeFirebaseFirestore()), antesDeCerrarSesion: (uid) async => orden.add('antes:$uid'));
    await s.cerrarSesion();
    expect(orden, ['signOut']);
    s.dispose();
  });
}
