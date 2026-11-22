// Etapa 6 — flujo de eliminación de cuenta en la app: reautenticación, cliente del Worker, controlador,
// sección de «Mi cuenta», bloqueo de acciones comerciales y representación de cafés suspendidos.
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/repositories/account_deletion_client.dart';
import 'package:lotea_cafe/repositories/auth_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/user_repository.dart';
import 'package:lotea_cafe/screens/seller/my_coffee_lots_screen.dart';
import 'package:lotea_cafe/state/account_deletion_controller.dart';
import 'package:lotea_cafe/state/session_provider.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/utils/account_block.dart';
import 'package:lotea_cafe/utils/format_utils.dart';
import 'package:lotea_cafe/widgets/account_deletion_section.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------------------------
// Dobles de prueba
// ---------------------------------------------------------------------------------------------

class _CredencialFalsa implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UsuarioReauth implements User {
  _UsuarioReauth({this.correo = 'ana@x.co'});
  final String? correo;
  final List<String> eventos = [];
  Object? errorReauth;

  @override
  String? get email => correo;

  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential credential) async {
    eventos.add('reauth');
    final e = errorReauth;
    if (e != null) throw e;
    return _CredencialFalsa();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    eventos.add('token:$forceRefresh');
    return 'id-token-nuevo';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FirebaseAuthFalso implements FirebaseAuth {
  _FirebaseAuthFalso(this.usuario);
  User? usuario;

  @override
  User? get currentUser => usuario;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthRepoFalso implements AuthRepository {
  final List<String> eventos = [];
  Object? error;
  Completer<void>? espera;

  @override
  Future<String> reautenticar(String password) async {
    eventos.add('reauth');
    final c = espera;
    if (c != null) await c.future;
    final e = error;
    if (e != null) throw e;
    return 'token-fresco';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClienteFalso implements AccountDeletionClient {
  final List<String> llamadas = [];
  Object? error;
  Completer<void>? espera;
  DateTime programada = DateTime.utc(2026, 11, 29, 17, 30);

  Future<EstadoEliminacionCuenta> _responder(String tipo, String token) async {
    llamadas.add('$tipo:$token');
    final c = espera;
    if (c != null) await c.future;
    final e = error;
    if (e != null) throw e;
    return tipo == 'solicitar'
        ? EstadoEliminacionCuenta(estado: 'eliminacionPendiente', solicitadaAt: DateTime.utc(2026, 11, 14, 17, 30), programadaAt: programada, retencionDias: 15)
        : const EstadoEliminacionCuenta(estado: 'activa');
  }

  @override
  Future<EstadoEliminacionCuenta> solicitar(String idToken) => _responder('solicitar', idToken);
  @override
  Future<EstadoEliminacionCuenta> cancelar(String idToken) => _responder('cancelar', idToken);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _config = ImageKitConfig(authEndpoint: 'https://a.workers.dev', publicKey: 'public_x=', cleanupEndpoint: 'https://imagekit-cleanup.x.workers.dev');

AccountDeletionClient _cliente(http.Client c, {ImageKitConfig config = _config, Duration timeout = const Duration(seconds: 5)}) =>
    AccountDeletionClient(client: c, config: config, timeout: timeout);

http.Response _json(int estado, Map<String, dynamic> cuerpo) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

AppUser _usuario({CuentaEstado estado = CuentaEstado.activa, DateTime? solicitada, DateTime? programada}) => AppUser(
      uid: 'ana', email: 'ana@x.co', nombre: 'Ana', rol: UserRole.vendedor, onboardingCompleto: true,
      cuentaEstado: estado, eliminacionSolicitadaAt: solicitada, eliminacionProgramadaAt: programada,
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  // -------------------------------------------------------------------------------------------
  group('AuthRepository.reautenticar', () {
    test('éxito: reautentica con la contraseña y devuelve un ID token recién emitido (getIdToken(true))', () async {
      final u = _UsuarioReauth();
      final repo = AuthRepository(auth: _FirebaseAuthFalso(u));
      final token = await repo.reautenticar('secreta123');
      expect(token, 'id-token-nuevo');
      expect(u.eventos, ['reauth', 'token:true']); // primero reautenticar, luego refrescar el token
    });

    test('contraseña incorrecta: error claro y NO se pide token', () async {
      for (final codigo in ['wrong-password', 'invalid-credential', 'invalid-login-credentials']) {
        final u = _UsuarioReauth()..errorReauth = FirebaseAuthException(code: codigo);
        await expectLater(
          AuthRepository(auth: _FirebaseAuthFalso(u)).reautenticar('mala'),
          throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.credencialesInvalidas).having((e) => e.mensaje, 'mensaje', 'La contraseña no es correcta.')),
        );
        expect(u.eventos, ['reauth'], reason: codigo);
      }
    });

    test('sin sesión (currentUser nulo): error de sesión y no se llama a nada', () async {
      await expectLater(
        AuthRepository(auth: _FirebaseAuthFalso(null)).reautenticar('x'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinSesion)),
      );
    });

    test('correo no disponible: error de validación y no se intenta reautenticar', () async {
      for (final correo in [null, '']) {
        final u = _UsuarioReauth(correo: correo);
        await expectLater(
          AuthRepository(auth: _FirebaseAuthFalso(u)).reautenticar('x'),
          throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion)),
        );
        expect(u.eventos, isEmpty);
      }
    });

    test('contraseña vacía: se rechaza sin llamar a Firebase', () async {
      final u = _UsuarioReauth();
      await expectLater(AuthRepository(auth: _FirebaseAuthFalso(u)).reautenticar(''), throwsA(isA<RepoException>()));
      expect(u.eventos, isEmpty);
    });

    test('pérdida de conexión → sinConexion; sesión que exige volver a entrar → sinSesion', () async {
      final red = _UsuarioReauth()..errorReauth = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(AuthRepository(auth: _FirebaseAuthFalso(red)).reautenticar('x'), throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinConexion)));
      final reciente = _UsuarioReauth()..errorReauth = FirebaseAuthException(code: 'requires-recent-login');
      await expectLater(AuthRepository(auth: _FirebaseAuthFalso(reciente)).reautenticar('x'), throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinSesion)));
    });

    test('los mensajes de error no contienen la contraseña', () async {
      final u = _UsuarioReauth()..errorReauth = FirebaseAuthException(code: 'wrong-password');
      try {
        await AuthRepository(auth: _FirebaseAuthFalso(u)).reautenticar('MiClaveSecreta!');
        fail('debía fallar');
      } on RepoException catch (e) {
        expect(e.mensaje.contains('MiClaveSecreta!'), isFalse);
        expect(e.toString().contains('MiClaveSecreta!'), isFalse);
      }
    });
  });

  // -------------------------------------------------------------------------------------------
  group('AccountDeletionClient', () {
    test('solicitar: POST a /account-deletion/request con el token, sin datos de la persona; devuelve lo que confirma el Worker', () async {
      late http.Request visto;
      final c = _cliente(MockClient((r) async {
        visto = r;
        return _json(200, {'estado': 'eliminacionPendiente', 'solicitadaAt': '2026-11-14T17:30:00.000Z', 'programadaAt': '2026-11-29T17:30:00.000Z', 'retencionDias': 15, 'idempotente': false});
      }));
      final r = await c.solicitar('TOK');
      expect(visto.method, 'POST');
      expect(visto.url.toString(), 'https://imagekit-cleanup.x.workers.dev/account-deletion/request');
      expect(visto.headers['Authorization'], 'Bearer TOK');
      expect(visto.body, '{}'); // ni uid, ni fechas, ni días: el servidor decide
      expect(r.pendiente, isTrue);
      expect(r.programadaAt!.toUtc(), DateTime.utc(2026, 11, 29, 17, 30));
      expect(r.retencionDias, 15);
    });

    test('cancelar: POST a /account-deletion/cancel', () async {
      late Uri url;
      final r = await _cliente(MockClient((req) async {
        url = req.url;
        return _json(200, {'estado': 'activa', 'idempotente': false, 'cafesRestaurados': 2});
      })).cancelar('TOK');
      expect(url.path, '/account-deletion/cancel');
      expect(r.estado, 'activa');
      expect(r.pendiente, isFalse);
    });

    test('el endpoint con ruta o barra final no rompe la URL', () async {
      late Uri url;
      const cfg = ImageKitConfig(authEndpoint: 'https://a.workers.dev', publicKey: 'p', cleanupEndpoint: 'https://imagekit-cleanup.x.workers.dev/');
      await _cliente(MockClient((req) async {
        url = req.url;
        return _json(200, {'estado': 'activa'});
      }), config: cfg).cancelar('T');
      expect(url.toString(), 'https://imagekit-cleanup.x.workers.dev/account-deletion/cancel');
    });

    test('401 de reautenticación → error de sesión que pide confirmar la contraseña (no éxito)', () async {
      await expectLater(
        _cliente(MockClient((_) async => _json(401, {'error': 'x', 'codigo': 'reautenticacion'}))).solicitar('T'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinSesion).having((e) => e.mensaje, 'mensaje', contains('contraseña'))),
      );
    });

    test('409 muestra el mensaje del servidor; 403, 429, 400 y 5xx tienen mensajes propios y claros', () async {
      Future<RepoException> fallo(int estado, [Map<String, dynamic> cuerpo = const {}]) async {
        try {
          await _cliente(MockClient((_) async => _json(estado, cuerpo))).solicitar('T');
        } on RepoException catch (e) {
          return e;
        }
        throw StateError('debía fallar');
      }

      final c409 = await fallo(409, {'error': 'El plazo para cancelar la solicitud ya terminó.', 'codigo': 'plazo_vencido'});
      expect(c409.tipo, RepoErrorKind.transicionInvalida);
      expect(c409.mensaje, 'El plazo para cancelar la solicitud ya terminó.');
      expect((await fallo(403)).tipo, RepoErrorKind.sinPermisos);
      expect((await fallo(429)).tipo, RepoErrorKind.otro);
      expect((await fallo(400)).tipo, RepoErrorKind.validacion);
      for (final s in [500, 502, 503]) {
        final e = await fallo(s, {'error': 'detalle interno del servidor'});
        expect(e.tipo, RepoErrorKind.otro);
        expect(e.mensaje.contains('detalle interno'), isFalse); // no se filtra texto del servidor en errores 5xx
      }
    });

    test('un 200 con cuerpo inválido NO se toma como éxito', () async {
      await expectLater(_cliente(MockClient((_) async => http.Response('<html>', 200))).solicitar('T'), throwsA(isA<RepoException>()));
      await expectLater(_cliente(MockClient((_) async => _json(200, {'otra': 'cosa'}))).solicitar('T'), throwsA(isA<RepoException>()));
    });

    test('fallo de red o tiempo agotado → sinConexion (nunca éxito)', () async {
      await expectLater(
        _cliente(MockClient((_) async => throw http.ClientException('sin red'))).solicitar('T'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinConexion)),
      );
      final colgado = Completer<http.Response>();
      await expectLater(
        _cliente(MockClient((_) => colgado.future), timeout: const Duration(milliseconds: 20)).solicitar('T'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinConexion)),
      );
    });

    test('sin endpoint configurado no se llama a la red', () async {
      var llamadas = 0;
      const sin = ImageKitConfig(authEndpoint: '', publicKey: '');
      await expectLater(
        _cliente(MockClient((_) async {
          llamadas++;
          return _json(200, {'estado': 'activa'});
        }), config: sin).solicitar('T'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.configuracionPendiente)),
      );
      expect(llamadas, 0);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('AccountDeletionController', () {
    test('reautentica y entrega al Worker el token fresco; devuelve el estado confirmado', () async {
      final auth = _AuthRepoFalso();
      final cliente = _ClienteFalso();
      final c = AccountDeletionController(auth: auth, client: cliente);
      final r = await c.solicitar('pw');
      expect(auth.eventos, ['reauth']);
      expect(cliente.llamadas, ['solicitar:token-fresco']);
      expect(r.pendiente, isTrue);
      expect(c.ocupado, isFalse);
      final cancelada = await c.cancelar('pw');
      expect(cliente.llamadas.last, 'cancelar:token-fresco');
      expect(cancelada.estado, 'activa');
    });

    test('si la reautenticación falla NO se llama al Worker', () async {
      final auth = _AuthRepoFalso()..error = const RepoException(RepoErrorKind.credencialesInvalidas, 'La contraseña no es correcta.');
      final cliente = _ClienteFalso();
      final c = AccountDeletionController(auth: auth, client: cliente);
      await expectLater(c.solicitar('mala'), throwsA(isA<RepoException>()));
      expect(cliente.llamadas, isEmpty);
      expect(c.ocupado, isFalse); // queda libre para reintentar
    });

    test('una segunda operación mientras hay una en curso se rechaza (no hay doble envío)', () async {
      final auth = _AuthRepoFalso();
      final cliente = _ClienteFalso()..espera = Completer<void>();
      final c = AccountDeletionController(auth: auth, client: cliente);
      final primera = c.solicitar('pw');
      await pumpEventQueue();
      expect(c.ocupado, isTrue);
      await expectLater(c.solicitar('pw'), throwsA(isA<RepoException>()));
      await expectLater(c.cancelar('pw'), throwsA(isA<RepoException>()));
      expect(auth.eventos, ['reauth']);
      expect(cliente.llamadas, ['solicitar:token-fresco']);
      cliente.espera!.complete();
      await primera;
      expect(c.ocupado, isFalse);
    });

    test('un fallo del Worker se propaga (no hay éxito falso) y permite reintentar', () async {
      final cliente = _ClienteFalso()..error = const RepoException(RepoErrorKind.sinConexion, 'Sin conexión.');
      final c = AccountDeletionController(auth: _AuthRepoFalso(), client: cliente);
      await expectLater(c.solicitar('pw'), throwsA(isA<RepoException>()));
      cliente.error = null;
      expect((await c.solicitar('pw')).pendiente, isTrue);
      expect(cliente.llamadas.length, 2);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('AccountDeletionSection («Mi cuenta»)', () {
    final programada = DateTime(2026, 11, 29, 17, 30);
    final solicitada = DateTime(2026, 11, 14, 17, 30);

    void pantalla(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2400);
      addTearDown(tester.view.reset);
    }

    Future<void> montar(WidgetTester tester, Widget seccion) async {
      pantalla(tester);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: SingleChildScrollView(child: seccion))));
    }

    Future<void> abrirYEscribir(WidgetTester tester, {String password = 'secreta', bool entiendo = true}) async {
      await tester.tap(find.byKey(const ValueKey('boton_eliminar_cuenta')));
      await tester.pumpAndSettle();
      if (entiendo) await tester.tap(find.byKey(const ValueKey('casilla_entiendo')));
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), password);
      await tester.pump();
    }

    final confirmar = find.byKey(const ValueKey('boton_confirmar_contrasena'));

    testWidgets('cuenta activa: muestra «Eliminar cuenta»; abrir el diálogo NO registra nada', (tester) async {
      var llamadas = 0;
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(),
        onSolicitar: (_) async { llamadas++; throw StateError('no debía llamarse'); },
        onCancelar: (_) async => throw StateError('no'),
      ));
      expect(find.text('Eliminar cuenta'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('boton_eliminar_cuenta')));
      await tester.pumpAndSettle();
      final d = find.byType(AlertDialog);
      expect(d, findsOneWidget);
      for (final frase in ['15 días calendario', 'se bloquearán las operaciones comerciales', 'cafés publicados dejarán de aparecer', 'borradores no se alterarán', 'historial de solicitudes, conversaciones y cotizaciones no se borra', 'cancelar la solicitud antes de la fecha límite', 'borrado definitivo todavía no ocurre']) {
        expect(find.descendant(of: d, matching: find.textContaining(frase)), findsOneWidget, reason: frase);
      }
      expect(llamadas, 0);
      await tester.tap(find.byKey(const ValueKey('boton_volver')));
      await tester.pumpAndSettle();
      expect(llamadas, 0); // cancelar el diálogo tampoco registra nada
    });

    testWidgets('exige confirmación explícita Y contraseña antes de poder enviar', (tester) async {
      await montar(tester, AccountDeletionSection(usuario: _usuario(), onSolicitar: (_) async => throw StateError('x'), onCancelar: (_) async => throw StateError('x')));
      await tester.tap(find.byKey(const ValueKey('boton_eliminar_cuenta')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(confirmar).onPressed, isNull); // nada marcado
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), 'secreta');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(confirmar).onPressed, isNull); // contraseña sin casilla
      await tester.tap(find.byKey(const ValueKey('casilla_entiendo')));
      await tester.pump();
      expect(tester.widget<ElevatedButton>(confirmar).onPressed, isNotNull);
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), '');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(confirmar).onPressed, isNull); // casilla sin contraseña
    });

    testWidgets('el campo de contraseña está oculto', (tester) async {
      await montar(tester, AccountDeletionSection(usuario: _usuario(), onSolicitar: (_) async => throw StateError('x'), onCancelar: (_) async => throw StateError('x')));
      await tester.tap(find.byKey(const ValueKey('boton_eliminar_cuenta')));
      await tester.pumpAndSettle();
      final campo = tester.widget<TextField>(find.byKey(const ValueKey('campo_contrasena')));
      expect(campo.obscureText, isTrue);
      expect(campo.enableSuggestions, isFalse);
    });

    testWidgets('solicitud exitosa: envía la contraseña una vez, cierra el diálogo y muestra la fecha programada del servidor', (tester) async {
      final recibidas = <String>[];
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(),
        onSolicitar: (p) async {
          recibidas.add(p);
          return EstadoEliminacionCuenta(estado: 'eliminacionPendiente', solicitadaAt: solicitada, programadaAt: programada, retencionDias: 15);
        },
        onCancelar: (_) async => throw StateError('x'),
      ));
      await abrirYEscribir(tester);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(recibidas, ['secreta']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining(formatFechaHora(programada)), findsOneWidget); // en el aviso de confirmación
    });

    testWidgets('evita el doble envío: dos toques seguidos generan UNA sola solicitud y se ve el progreso', (tester) async {
      final espera = Completer<EstadoEliminacionCuenta>();
      var llamadas = 0;
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(),
        onSolicitar: (_) { llamadas++; return espera.future; },
        onCancelar: (_) async => throw StateError('x'),
      ));
      await abrirYEscribir(tester);
      await tester.tap(confirmar);
      await tester.tap(confirmar); // sin pump entre toques
      await tester.pump();
      expect(llamadas, 1);
      expect(find.byKey(const ValueKey('enviando_progreso')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(confirmar).onPressed, isNull);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('boton_volver'))).onPressed, isNull);
      espera.complete(EstadoEliminacionCuenta(estado: 'eliminacionPendiente', programadaAt: programada));
      await tester.pumpAndSettle();
      expect(llamadas, 1);
    });

    testWidgets('contraseña incorrecta o error de red/Worker: se muestra el error, NO el éxito, y se puede reintentar', (tester) async {
      var intento = 0;
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(),
        onSolicitar: (_) async {
          intento++;
          if (intento == 1) throw const RepoException(RepoErrorKind.credencialesInvalidas, 'La contraseña no es correcta.');
          if (intento == 2) throw const RepoException(RepoErrorKind.sinConexion, 'No hay conexión con el servidor.');
          return EstadoEliminacionCuenta(estado: 'eliminacionPendiente', programadaAt: programada);
        },
        onCancelar: (_) async => throw StateError('x'),
      ));
      await abrirYEscribir(tester, password: 'mala');
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(find.text('La contraseña no es correcta.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Solicitud registrada'), findsNothing);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión con el servidor.'), findsOneWidget);
      expect(find.textContaining('Solicitud registrada'), findsNothing);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(intento, 3);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Solicitud registrada'), findsOneWidget);
    });

    testWidgets('la contraseña no se conserva: al cerrar y volver a abrir el diálogo el campo está vacío', (tester) async {
      await montar(tester, AccountDeletionSection(usuario: _usuario(), onSolicitar: (_) async => throw StateError('x'), onCancelar: (_) async => throw StateError('x')));
      await abrirYEscribir(tester, password: 'MiClave');
      await tester.tap(find.byKey(const ValueKey('boton_volver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('boton_eliminar_cuenta')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('campo_contrasena'))).controller!.text, isEmpty);
    });

    testWidgets('cuenta pendiente: tarjeta con la fecha programada, el plazo de 15 días y «Cancelar solicitud»', (tester) async {
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(estado: CuentaEstado.eliminacionPendiente, solicitada: solicitada, programada: programada),
        onSolicitar: (_) async => throw StateError('x'),
        onCancelar: (_) async => throw StateError('x'),
      ));
      expect(find.text('Eliminación de cuenta solicitada'), findsOneWidget);
      expect(find.textContaining(formatFechaHora(programada)), findsOneWidget);
      expect(find.textContaining('15 días'), findsWidgets);
      expect(find.byKey(const ValueKey('boton_cancelar_eliminacion')), findsOneWidget);
      expect(find.byKey(const ValueKey('boton_eliminar_cuenta')), findsNothing); // no se puede volver a solicitar
    });

    testWidgets('cancelar: pide contraseña, llama al Worker una vez y la UI vuelve a «Eliminar cuenta» cuando Firestore la reactiva', (tester) async {
      var usuario = _usuario(estado: CuentaEstado.eliminacionPendiente, solicitada: solicitada, programada: programada);
      final cancelaciones = <String>[];
      late StateSetter refrescar;
      pantalla(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(builder: (context, setState) {
              refrescar = setState;
              return AccountDeletionSection(
                usuario: usuario,
                        onSolicitar: (_) async => throw StateError('x'),
                onCancelar: (p) async {
                  cancelaciones.add(p);
                  return const EstadoEliminacionCuenta(estado: 'activa');
                },
              );
            }),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('boton_cancelar_eliminacion')));
      await tester.pumpAndSettle();
      expect(cancelaciones, isEmpty); // abrir el diálogo no cancela
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), 'secreta');
      await tester.pump();
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(cancelaciones, ['secreta']);
      expect(find.textContaining('Solicitud cancelada'), findsOneWidget);
      // El estado REAL llega por Firestore: hasta entonces la tarjeta no se da por cancelada.
      expect(find.text('Eliminación de cuenta solicitada'), findsOneWidget);
      refrescar(() => usuario = _usuario());
      await tester.pump();
      expect(find.text('Eliminación de cuenta solicitada'), findsNothing);
      expect(find.byKey(const ValueKey('boton_eliminar_cuenta')), findsOneWidget);
    });

    testWidgets('error al cancelar: no se muestra éxito y la tarjeta sigue', (tester) async {
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(estado: CuentaEstado.eliminacionPendiente, solicitada: solicitada, programada: programada),
        onSolicitar: (_) async => throw StateError('x'),
        onCancelar: (_) async => throw const RepoException(RepoErrorKind.sinConexion, 'No hay conexión con el servidor.'),
      ));
      await tester.tap(find.byKey(const ValueKey('boton_cancelar_eliminacion')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), 'secreta');
      await tester.pump();
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión con el servidor.'), findsOneWidget);
      expect(find.textContaining('Solicitud cancelada'), findsNothing);
      expect(find.text('Eliminación de cuenta solicitada'), findsOneWidget);
    });

    testWidgets('la hora del teléfono no decide: con la fecha programada ya pasada en el reloj local el botón sigue visible y el servidor responde plazo_vencido', (tester) async {
      var intentos = 0;
      await montar(tester, AccountDeletionSection(
        // Fechas muy anteriores a la hora real del dispositivo: antes ocultaban el botón.
        usuario: _usuario(estado: CuentaEstado.eliminacionPendiente, solicitada: DateTime(2020, 1, 1), programada: DateTime(2020, 1, 16)),
        onSolicitar: (_) async => throw StateError('x'),
        onCancelar: (_) async {
          intentos++;
          throw const RepoException(RepoErrorKind.transicionInvalida, 'El plazo para cancelar la solicitud ya terminó.');
        },
      ));
      expect(find.byKey(const ValueKey('boton_cancelar_eliminacion')), findsOneWidget);
      expect(find.byKey(const ValueKey('eliminacion_plazo_vencido')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('boton_cancelar_eliminacion')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('campo_contrasena')), 'secreta');
      await tester.pump();
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(intentos, 1); // la decisión se pidió al servidor
      expect(find.text('El plazo para cancelar la solicitud ya terminó.'), findsOneWidget); // mensaje del servidor
      expect(find.textContaining('Solicitud cancelada'), findsNothing);
      expect(find.text('Eliminación de cuenta solicitada'), findsOneWidget);
    });

    testWidgets('estado de cuenta desconocido: aviso conservador y sin acciones de eliminación', (tester) async {
      await montar(tester, AccountDeletionSection(
        usuario: _usuario(estado: CuentaEstado.desconocida),
        onSolicitar: (_) async => throw StateError('x'),
        onCancelar: (_) async => throw StateError('x'),
      ));
      expect(find.byKey(const ValueKey('tarjeta_cuenta_desconocida')), findsOneWidget);
      expect(find.byKey(const ValueKey('boton_eliminar_cuenta')), findsNothing);
      expect(find.byKey(const ValueKey('boton_cancelar_eliminacion')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('cuenta pendiente: sesión abierta y acciones comerciales bloqueadas', () {
    Future<(SessionProvider, StreamController<User?>, List<String>, FakeFirebaseFirestore)> sesion(Map<String, dynamic> extra) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('ana').set({'uid': 'ana', 'email': 'ana@x.co', 'nombre': 'Ana', 'rol': 'vendedor', 'onboardingCompleto': true, ...extra});
      final eventos = <String>[];
      final auth = _AuthSesionFalso(eventos);
      final s = SessionProvider(auth: auth, users: UserRepository(db: db));
      auth.controlador.add(_UsuarioUid('ana'));
      await pumpEventQueue();
      return (s, auth.controlador, eventos, db);
    }

    test('la cuenta pendiente mantiene la sesión iniciada, ve su estado y puede cerrar sesión voluntariamente', () async {
      final (s, _, eventos, _) = await sesion({
        'cuentaEstado': 'eliminacionPendiente',
        'eliminacionSolicitadaAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
        'eliminacionProgramadaAt': Timestamp.fromDate(DateTime.utc(2026, 11, 29)),
      });
      expect(s.status, SessionStatus.listo);
      expect(s.autenticado, isTrue); // NO se fuerza signOut al registrar la solicitud
      expect(s.usuario!.eliminacionPendiente, isTrue);
      expect(s.operacionesBloqueadas, isTrue);
      expect(eventos, isEmpty);
      await s.cerrarSesion();
      expect(eventos, ['signOut']);
      s.dispose();
    });

    test('la cuenta activa (o sin campo) no está bloqueada', () async {
      final (s, _, _, _) = await sesion({});
      expect(s.operacionesBloqueadas, isFalse);
      s.dispose();
    });

    test('el cambio de estado que llega por Firestore (cancelación) reactiva la sesión sin reiniciarla', () async {
      final (s, _, _, db) = await sesion({'cuentaEstado': 'eliminacionPendiente'});
      expect(s.operacionesBloqueadas, isTrue);
      await db.collection('users').doc('ana').update({'cuentaEstado': 'activa', 'eliminacionSolicitadaAt': null, 'eliminacionProgramadaAt': null});
      await pumpEventQueue();
      expect(s.operacionesBloqueadas, isFalse);
      expect(s.status, SessionStatus.listo);
      s.dispose();
    });

    testWidgets('avisarSiCuentaBloqueada: con la cuenta pendiente bloquea y explica por qué; con la activa no hace nada', (tester) async {
      for (final (extra, bloquea) in [
        (<String, dynamic>{'cuentaEstado': 'eliminacionPendiente'}, true),
        (<String, dynamic>{}, false),
      ]) {
        final (s, _, _, _) = await tester.runAsync(() => sesion(extra)) as (SessionProvider, StreamController<User?>, List<String>, FakeFirebaseFirestore);
        bool? resultado;
        await tester.pumpWidget(ChangeNotifierProvider<SessionProvider>.value(
          value: s,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(builder: (context) => ElevatedButton(onPressed: () => resultado = avisarSiCuentaBloqueada(context), child: const Text('Enviar solicitud'))),
            ),
          ),
        ));
        await tester.tap(find.text('Enviar solicitud'));
        await tester.pump();
        expect(resultado, bloquea);
        expect(find.text(mensajeCuentaBloqueada), bloquea ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
        s.dispose();
      }
    });
  });

  // -------------------------------------------------------------------------------------------
  group('cafés suspendidos o de estado desconocido en «Mi catálogo»', () {
    CoffeeLot lote(String id, EstadoLote estado) => CoffeeLot(
          id: id, sellerId: 'ana', nombre: 'Caturra $id', variedades: const ['Caturra'], proceso: 'Lavado', precioCOP: 32000,
          fotos: const [], fotosStoragePaths: const [], sellerNombreMarca: 'Finca', departamento: 'Huila', region: 'Huila', estado: estado,
        );

    Future<void> montar(WidgetTester tester, CoffeeLot l) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: FilaCafe(lote: l, onTap: () => fail('no debe abrirse'), onEliminar: () => fail('no debe eliminarse'), onReintentarEliminacion: () => fail('no')))),
      ));
    }

    testWidgets('un café suspendido se muestra como «Suspendido» (solo informativo): ni editar, ni completar, ni eliminar, ni borrador', (tester) async {
      await montar(tester, lote('1', EstadoLote.suspendido));
      expect(find.text('Suspendido'), findsOneWidget);
      expect(find.byKey(const ValueKey('cafe_informativo_1')), findsOneWidget);
      expect(find.text('Borrador'), findsNothing);
      expect(find.text('Completar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(find.byTooltip('Eliminar café'), findsNothing);
      await tester.tap(find.text('Caturra 1'));
      await tester.pump(); // si abriera el formulario, el callback `fail` lo detectaría
    });

    testWidgets('un estado desconocido NO se muestra como borrador editable', (tester) async {
      await montar(tester, lote('2', EstadoLote.desconocido));
      expect(find.text('Estado no reconocido'), findsOneWidget);
      expect(find.text('Borrador'), findsNothing);
      expect(find.text('Completar'), findsNothing);
      expect(find.byTooltip('Eliminar café'), findsNothing);
    });

    testWidgets('un borrador y un café publicado conservan sus acciones de siempre', (tester) async {
      await montar(tester, lote('3', EstadoLote.borrador));
      expect(find.text('Completar'), findsOneWidget);
      expect(find.byTooltip('Eliminar café'), findsOneWidget);
    });
  });
}

// Dobles de sesión (mismo patrón que session_logout_hook_test.dart)
class _UsuarioUid implements User {
  @override
  final String uid;
  _UsuarioUid(this.uid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthSesionFalso implements AuthRepository {
  final controlador = StreamController<User?>.broadcast();
  final List<String> orden;
  _AuthSesionFalso(this.orden);

  @override
  Stream<User?> get authStateChanges => controlador.stream;
  @override
  Future<void> cerrarSesion() async => orden.add('signOut');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
