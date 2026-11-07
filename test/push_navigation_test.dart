import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/services/push_gateway.dart';
import 'package:lotea_cafe/services/push_navigation.dart';

class _GatewayFalso implements PushGateway {
  final primerPlano = StreamController<PushMensaje>.broadcast();
  final abrir = StreamController<PushMensaje>.broadcast();
  PushMensaje? inicial;

  @override
  Stream<PushMensaje> get enPrimerPlano => primerPlano.stream;
  @override
  Stream<PushMensaje> get alAbrirNotificacion => abrir.stream;
  @override
  Future<PushMensaje?> get mensajeInicial async => inicial;

  @override
  Future<PushPermiso> estadoPermiso() async => PushPermiso.concedido;
  @override
  Future<PushPermiso> pedirPermiso() async => PushPermiso.concedido;
  @override
  Future<String?> obtenerToken() async => null;
  @override
  Future<void> eliminarToken() async {}
  @override
  Stream<String> get tokenRenovado => Stream<String>.empty();
}

PushMensaje _msg(String ruta, String id, {String? messageId}) => PushMensaje(id: messageId, ruta: ruta, destinoId: id);

class _Entorno {
  final navegador = GlobalKey<NavigatorState>();
  final gateway = _GatewayFalso();
  final List<(PushDestino, String)> resoluciones = [];
  Widget? Function(PushDestino) pantalla = (d) => Scaffold(body: Text('PANTALLA ${d.ruta.name} ${d.id}'));
  Object? error;

  /// Si se fija, el resolver espera a que se complete (simula una consulta lenta de acceso).
  Completer<void>? compuerta;
  late final PushCoordinator coordinador;

  _Entorno() {
    coordinador = PushCoordinator(
      gateway: gateway,
      navegador: navegador,
      resolver: (d, uid) async {
        resoluciones.add((d, uid));
        final espera = compuerta;
        if (espera != null) await espera.future;
        if (error != null) throw error!;
        return pantalla(d);
      },
    );
  }

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(navigatorKey: navegador, home: const Scaffold(body: Text('INICIO'))));
    coordinador.iniciar();
    await tester.pump();
  }

  void sesionLista([String uid = 'ana']) => coordinador.actualizarSesion(uid: uid, lista: true, sinSesion: false);
  void sesionCargando() => coordinador.actualizarSesion(uid: null, lista: false, sinSesion: false);
  void sinSesion() => coordinador.actualizarSesion(uid: null, lista: false, sinSesion: true);
}

/// Deja que se entregue el evento del stream, termine el resolver y acaben las
/// animaciones. Un solo `pump(400ms)` no basta: el reloj del test avanza ANTES de
/// construir el primer fotograma, así que una ruta o un SnackBar recién añadidos se
/// construyen con la animación en 0 (el SnackBar aún fuera de pantalla). `pumpAndSettle`
/// sigue bombeando fotogramas hasta que la transición termina de verdad.
Future<void> _asentar(WidgetTester tester) async {
  await tester.pump(); // entrega el evento y ejecuta el resolver
  await tester.pumpAndSettle(); // completa la transición / animación de entrada
}

void main() {
  group('PushDestino.desde', () {
    test('acepta chat y cotización con ids de forma válida', () {
      expect(PushDestino.desde(_msg('chat', 'buyer1_lot1')), const PushDestino(PushRuta.chat, 'buyer1_lot1'));
      expect(PushDestino.desde(_msg('cotizacion', 'q-1')), const PushDestino(PushRuta.cotizacion, 'q-1'));
    });

    test('ignora rutas desconocidas, ids vacíos o con caracteres peligrosos', () {
      expect(PushDestino.desde(_msg('otra', 'x')), isNull);
      expect(PushDestino.desde(const PushMensaje(ruta: 'chat')), isNull);
      expect(PushDestino.desde(const PushMensaje(destinoId: 'x')), isNull);
      expect(PushDestino.desde(_msg('chat', '')), isNull);
      expect(PushDestino.desde(_msg('chat', '../users/otro')), isNull);
      expect(PushDestino.desde(_msg('chat', 'a/b')), isNull);
    });
  });

  group('al tocar una notificación', () {
    testWidgets('con sesión lista abre el chat correspondiente tras comprobar el acceso con el uid actual', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista('ana');
      e.gateway.abrir.add(_msg('chat', 'buyer1_lot1'));
      await _asentar(tester);
      expect(find.text('PANTALLA chat buyer1_lot1'), findsOneWidget);
      expect(e.navegador.currentState!.canPop(), isTrue, reason: 'la ruta de destino debe estar apilada sobre el inicio');
      expect(e.resoluciones.single.$2, 'ana');
    });

    testWidgets('una cotización abre el detalle de esa cotización', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      e.gateway.abrir.add(_msg('cotizacion', 'q1'));
      await _asentar(tester);
      expect(find.text('PANTALLA cotizacion q1'), findsOneWidget);
    });

    testWidgets('mientras la sesión se resuelve conserva el destino y navega cuando está lista', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionCargando();
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(e.coordinador.pendiente, const PushDestino(PushRuta.chat, 'c1'));
      expect(find.text('INICIO'), findsOneWidget);
      expect(e.resoluciones, isEmpty);

      e.sesionLista();
      await _asentar(tester);
      expect(e.coordinador.pendiente, isNull);
      expect(find.text('PANTALLA chat c1'), findsOneWidget);
    });

    testWidgets('con la app cerrada: getInitialMessage se conserva y se abre al estar lista la sesión', (tester) async {
      final e = _Entorno();
      e.gateway.inicial = _msg('cotizacion', 'q9', messageId: 'm-inicial');
      await e.montar(tester);
      expect(e.coordinador.pendiente, const PushDestino(PushRuta.cotizacion, 'q9'));
      e.sesionLista();
      await _asentar(tester);
      expect(find.text('PANTALLA cotizacion q9'), findsOneWidget);
    });

    testWidgets('con el onboarding sin terminar no navega todavía', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.coordinador.actualizarSesion(uid: 'ana', lista: false, sinSesion: false);
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(e.resoluciones, isEmpty);
      expect(e.coordinador.pendiente, isNotNull);
    });

    testWidgets('sin sesión descarta el destino: no se navega al contenido de nadie', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sinSesion();
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(e.coordinador.pendiente, isNull);
      expect(e.resoluciones, isEmpty);
      expect(find.text('INICIO'), findsOneWidget);
    });

    testWidgets('si la persona no tiene acceso (resolver devuelve null) no navega y lo explica', (tester) async {
      final e = _Entorno()..pantalla = (_) => null;
      await e.montar(tester);
      e.sesionLista();
      e.gateway.abrir.add(_msg('chat', 'ajeno'));
      await _asentar(tester);
      expect(find.text('INICIO'), findsOneWidget);
      expect(find.text('Este contenido ya no está disponible.'), findsOneWidget);
    });

    testWidgets('si falla la comprobación (red) no navega ni rompe: muestra un aviso', (tester) async {
      final e = _Entorno()..error = StateError('sin red');
      await e.montar(tester);
      e.sesionLista();
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(find.text('INICIO'), findsOneWidget);
      expect(find.text('No se pudo abrir la notificación. Inténtalo de nuevo.'), findsOneWidget);
    });

    testWidgets('mensajes sin ruta válida se ignoran', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      e.gateway.abrir.add(const PushMensaje(ruta: 'desconocida', destinoId: 'x'));
      await _asentar(tester);
      expect(e.resoluciones, isEmpty);
    });

    testWidgets('el mismo mensaje entregado por dos vías (inicial y onMessageOpenedApp) se abre una sola vez', (tester) async {
      final e = _Entorno();
      e.gateway.inicial = _msg('chat', 'c1', messageId: 'mismo');
      await e.montar(tester);
      e.sesionLista();
      e.gateway.abrir.add(_msg('chat', 'c1', messageId: 'mismo'));
      await _asentar(tester);
      expect(e.resoluciones, hasLength(1));
    });

    testWidgets('una segunda notificación que llega mientras se resuelve la primera no se pierde', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      final compuerta = Completer<void>();
      e.compuerta = compuerta;
      e.gateway.abrir.add(_msg('chat', 'c1', messageId: 'a'));
      await tester.pump();
      expect(e.resoluciones, hasLength(1)); // la primera sigue resolviéndose

      e.gateway.abrir.add(_msg('cotizacion', 'q2', messageId: 'b'));
      await tester.pump();
      expect(e.coordinador.pendiente, const PushDestino(PushRuta.cotizacion, 'q2'));

      e.compuerta = null;
      compuerta.complete();
      await _asentar(tester);
      expect(e.resoluciones.map((r) => r.$1.id), ['c1', 'q2']);
      expect(e.coordinador.pendiente, isNull);
      expect(find.text('PANTALLA cotizacion q2'), findsOneWidget);
    });

    testWidgets('si cambia la cuenta mientras se comprueba el acceso no se abre el destino', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista('ana');
      final compuerta = Completer<void>();
      e.compuerta = compuerta;
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await tester.pump();
      expect(e.resoluciones.single.$2, 'ana');

      e.sesionLista('luis'); // otra cuenta entra antes de que termine la comprobación de 'ana'
      compuerta.complete();
      await _asentar(tester);
      expect(find.text('PANTALLA chat c1'), findsNothing);
      expect(find.text('INICIO'), findsOneWidget);
      expect(e.navegador.currentState!.canPop(), isFalse);
      expect(e.coordinador.pendiente, isNull);
    });

    testWidgets('si ese chat ya está abierto no se abre otra copia', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      e.coordinador.chatAbierto = 'c1';
      e.gateway.abrir.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(e.resoluciones, isEmpty);
    });
  });

  group('con la app en primer plano', () {
    testWidgets('muestra un aviso dentro de la app con texto genérico (sin contenido privado)', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      e.gateway.primerPlano.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(find.text('Tienes un nuevo mensaje en Lotea Café'), findsOneWidget);
      expect(find.text('Ver'), findsOneWidget);
      expect(e.resoluciones, isEmpty); // solo avisa; no navega por sí solo
    });

    testWidgets('una cotización muestra «Tienes novedades en una cotización»', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.gateway.primerPlano.add(_msg('cotizacion', 'q1'));
      await _asentar(tester);
      expect(find.text('Tienes novedades en una cotización'), findsOneWidget);
    });

    testWidgets('«Ver» abre el destino', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.sesionLista();
      e.gateway.primerPlano.add(_msg('cotizacion', 'q1'));
      await _asentar(tester);
      final ver = find.text('Ver');
      expect(ver, findsOneWidget);
      // El SnackBar ya terminó de entrar: el botón está dentro de la pantalla y recibe toques.
      final alto = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getCenter(ver).dy, lessThan(alto), reason: '«Ver» debe estar dentro del área visible');
      expect(ver.hitTestable(), findsOneWidget, reason: '«Ver» debe poder recibir el toque');
      await tester.tap(ver);
      await _asentar(tester);
      expect(find.text('PANTALLA cotizacion q1'), findsOneWidget);
    });

    testWidgets('con ese chat a la vista no se muestra aviso', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.coordinador.chatAbierto = 'c1';
      e.gateway.primerPlano.add(_msg('chat', 'c1'));
      await _asentar(tester);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('un mensaje sin ruta válida no muestra nada', (tester) async {
      final e = _Entorno();
      await e.montar(tester);
      e.gateway.primerPlano.add(const PushMensaje(ruta: 'x', destinoId: 'y'));
      await _asentar(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
