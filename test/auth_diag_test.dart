import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/auth_repository.dart';
import 'package:lotea_cafe/repositories/user_repository.dart';
import 'package:lotea_cafe/services/auth_diag.dart';
import 'package:lotea_cafe/services/session_preference.dart';
import 'package:lotea_cafe/state/session_provider.dart';

// Datos "privados" de mentira: ninguno puede aparecer jamás en una línea [AUTH_DIAG].
const _uidSecreto = 'UID-SECRETO-123';
const _correoSecreto = 'secreto@example.com';
const _claveSecreta = 'clave-secreta-xyz';
const _mensajeDeError = 'mensaje-interno-del-error';

class _UsuarioFalso implements User {
  @override
  final String uid;
  _UsuarioFalso(this.uid);

  @override
  String? get email => _correoSecreto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Cerrar sesión emite `null` como lo hace Firebase; `usuarioActual` es controlable.
class _AuthFalso implements AuthRepository {
  final controlador = StreamController<User?>.broadcast();
  User? actual;
  int fallosDeCierre;
  _AuthFalso({this.fallosDeCierre = 0});

  @override
  Stream<User?> get authStateChanges => controlador.stream;

  @override
  User? get usuarioActual => actual;

  @override
  Future<User> iniciarSesion({required String email, required String password}) async {
    final u = _UsuarioFalso(_uidSecreto);
    actual = u;
    return u;
  }

  @override
  Future<void> cerrarSesion() async {
    if (fallosDeCierre > 0) {
      fallosDeCierre--;
      throw StateError(_mensajeDeError);
    }
    actual = null;
    controlador.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FakeFirebaseFirestore> _baseConUsuario() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(_uidSecreto).set({
    'uid': _uidSecreto,
    'email': _correoSecreto,
    'nombre': 'Nombre Privado',
    'rol': 'comprador',
    'onboardingCompleto': true,
  });
  return db;
}

SessionProvider _sesion(_AuthFalso auth, FakeFirebaseFirestore db, {PreferenciaSesion? preferencia}) =>
    SessionProvider(auth: auth, users: UserRepository(db: db), preferencia: preferencia);

void _sinDatosPrivados(String registro) {
  expect(registro, isNot(contains(_uidSecreto)));
  expect(registro, isNot(contains(_correoSecreto)));
  expect(registro, isNot(contains(_claveSecreta)));
  expect(registro, isNot(contains('Nombre Privado')));
  expect(registro, isNot(contains(_mensajeDeError)));
}

void main() {
  late List<String> lineas;

  setUp(() {
    lineas = <String>[];
    AuthDiag.sumidero = lineas.add;
  });

  tearDown(() {
    AuthDiag.sumidero = null;
  });

  test('sesión restaurada con preferencia activada: registra creación, evento y decisión de conservar', () async {
    final auth = _AuthFalso();
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria());

    final usuario = _UsuarioFalso(_uidSecreto);
    auth.actual = usuario; // Firebase ya tiene usuario actual cuando emite el primer evento
    auth.controlador.add(usuario);
    await pumpEventQueue();

    final todo = lineas.join('\n');
    expect(lineas.every((l) => l.startsWith('[AUTH_DIAG]')), isTrue);
    expect(todo, contains('SessionProvider creado: currentUser=null mantener_sesion=true'));
    expect(todo, contains('authStateChanges evento: primero=true user=no_null currentUser=no_null'));
    expect(todo, contains('comparacion=mismo_usuario'));
    expect(todo, contains('decisión: CONSERVAR sesión restaurada, razón=mantener_sesion=true'));
    expect(todo, contains('estado: iniciando -> cargandoPerfil'));
    expect(todo, isNot(contains('CERRAR sesión restaurada')));
    expect(s.status, SessionStatus.listo);
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('primer evento con usuario nulo: lo registra y pasa a sinSesion', () async {
    final auth = _AuthFalso();
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria());

    auth.controlador.add(null);
    await pumpEventQueue();

    final todo = lineas.join('\n');
    expect(todo, contains('authStateChanges evento: primero=true user=null currentUser=null'));
    expect(todo, contains('comparacion=ambos_null'));
    expect(todo, contains('estado: iniciando -> sinSesion (evento user=null)'));
    expect(todo, isNot(contains('decisión:')));
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('preferencia desactivada: registra la razón del cierre automático y el antes/después de signOut', () async {
    final auth = _AuthFalso();
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria(mantener: false));

    final usuario = _UsuarioFalso(_uidSecreto);
    auth.actual = usuario;
    auth.controlador.add(usuario);
    await pumpEventQueue();

    final todo = lineas.join('\n');
    expect(todo, contains('decisión: CERRAR sesión restaurada automáticamente, razón=primer_evento_con_usuario_y_mantener_sesion=false'));
    expect(todo, contains('signOut AUTOMÁTICO: antes (currentUser=no_null)'));
    expect(todo, contains('signOut AUTOMÁTICO: después, sin excepción (currentUser=null)'));
    expect(todo, contains('authStateChanges evento: primero=false user=null'));
    expect(todo, isNot(contains('signOut MANUAL')));
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('si el cierre automático falla: registra solo el tipo de la excepción, nunca su mensaje', () async {
    final auth = _AuthFalso(fallosDeCierre: 1);
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria(mantener: false));

    final usuario = _UsuarioFalso(_uidSecreto);
    auth.actual = usuario;
    auth.controlador.add(usuario);
    await pumpEventQueue();

    final todo = lineas.join('\n');
    expect(todo, contains('signOut AUTOMÁTICO: FALLÓ tipo=StateError'));
    expect(todo, isNot(contains('signOut AUTOMÁTICO: después')));
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('cierre manual: se distingue del automático y registra antes/después', () async {
    final auth = _AuthFalso();
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria());

    final usuario = _UsuarioFalso(_uidSecreto);
    auth.actual = usuario;
    auth.controlador.add(usuario);
    await pumpEventQueue();
    expect(s.status, SessionStatus.listo);

    await s.cerrarSesion();
    await pumpEventQueue();

    final todo = lineas.join('\n');
    expect(todo, contains('signOut MANUAL: antes (currentUser=no_null)'));
    expect(todo, contains('signOut MANUAL: después, sin excepción (currentUser=null)'));
    expect(todo, isNot(contains('signOut AUTOMÁTICO')));
    expect(todo, contains('estado: listo -> sinSesion (evento user=null)'));
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('inicio de sesión normal: registra si Firebase tiene usuario actual, sin correo ni contraseña', () async {
    final auth = _AuthFalso();
    final s = _sesion(auth, await _baseConUsuario(), preferencia: PreferenciaSesion.enMemoria());

    await s.iniciarSesion(email: _correoSecreto, password: _claveSecreta);

    final todo = lineas.join('\n');
    expect(todo, contains('inicio de sesión normal completado: currentUser=no_null'));
    _sinDatosPrivados(todo);
    s.dispose();
  });

  test('la lectura de mantener_sesion registra solo el booleano (o que se usó el valor por defecto)', () async {
    await PreferenciaSesion.cargar(_AlmacenFijo(false));
    await PreferenciaSesion.cargar(_AlmacenFijo(null));
    await PreferenciaSesion.cargar(_AlmacenQueFalla());

    final todo = lineas.join('\n');
    expect(todo, contains('mantener_sesion almacenamiento: guardado=false'));
    expect(todo, contains('mantener_sesion almacenamiento: guardado=sin_valor(se_usa_true_por_defecto)'));
    expect(todo, contains('mantener_sesion almacenamiento: lectura FALLÓ tipo=StateError'));
    _sinDatosPrivados(todo);
  });

  test('AuthDiag.comparar y actualNulo nunca lanzan ni imprimen el UID', () {
    expect(AuthDiag.actualNulo(() => throw StateError('x')), 'no_disponible');
    expect(AuthDiag.comparar(null, () => throw StateError('x')), 'actual_no_disponible');
    expect(AuthDiag.comparar(_UsuarioFalso('a'), () => _UsuarioFalso('b')), 'usuarios_distintos');
    expect(AuthDiag.comparar(_UsuarioFalso('a'), () => null), 'emitido_presente_actual_null');
    expect(AuthDiag.comparar(null, () => _UsuarioFalso('a')), 'emitido_null_actual_presente');
    expect(AuthDiag.booleano(null), 'sin_preferencia');
    expect(AuthDiag.tipo(StateError(_mensajeDeError)), 'StateError');
    expect(AuthDiag.tipo(FirebaseAuthException(code: 'network-request-failed', message: _mensajeDeError)),
        'FirebaseAuthException(code=network-request-failed)');
  });
}

class _AlmacenFijo implements AlmacenPreferenciaSesion {
  final bool? valor;
  _AlmacenFijo(this.valor);

  @override
  Future<bool?> leer() async => valor;

  @override
  Future<void> guardar(bool mantener) async {}
}

class _AlmacenQueFalla implements AlmacenPreferenciaSesion {
  @override
  Future<bool?> leer() async => throw StateError(_mensajeDeError);

  @override
  Future<void> guardar(bool mantener) async {}
}
