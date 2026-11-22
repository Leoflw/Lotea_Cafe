// Etapa 7.0 — compatibilidad de la app con la futura eliminación definitiva de cuentas.
// Solo lectura y presentación: no se escribe ningún marcador en Firestore ni se llama a ningún Worker.
// Las reglas de Firestore NO se ejecutan aquí (siguen cubiertas por rules-tests/, sin cambios).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/chat_message.dart';
import 'package:lotea_cafe/models/cuenta_eliminada.dart';
import 'package:lotea_cafe/models/interest_request.dart';
import 'package:lotea_cafe/models/quote_request.dart';
import 'package:lotea_cafe/repositories/chat_repository.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';
import 'package:lotea_cafe/repositories/quote_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/screens/chat/chat_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_detail_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_widgets.dart';
import 'package:lotea_cafe/services/push_navigation.dart';
import 'package:lotea_cafe/state/session_provider.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/utils/account_block.dart';
import 'package:lotea_cafe/utils/format_utils.dart';
import 'package:lotea_cafe/widgets/account_deletion_section.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------------------------
// Dobles de prueba (ninguno toca Firebase real).
// ---------------------------------------------------------------------------------------------

class _SesionFalsa extends ChangeNotifier implements SessionProvider {
  _SesionFalsa(this._usuario, {this.bloqueada = false});
  final AppUser _usuario;
  final bool bloqueada;

  @override
  AppUser? get usuario => _usuario;

  @override
  bool get operacionesBloqueadas => bloqueada;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PushFalso implements PushCoordinator {
  @override
  String? chatAbierto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConexionesFalsas extends InterestRequestRepository {
  _ConexionesFalsas(this.conexion) : super(db: FakeFirebaseFirestore());
  final InterestRequest conexion;

  @override
  Stream<InterestRequest?> observar(String id) => Stream.value(conexion);
}

class _ChatsFalso extends ChatRepository {
  _ChatsFalso(this.mensajes) : super(db: FakeFirebaseFirestore());
  final List<ChatMessage> mensajes;

  @override
  Stream<List<ChatMessage>> observar(String chatId) => Stream.value(mensajes);
}

class _CotizacionesFalsas extends QuoteRepository {
  _CotizacionesFalsas(this.cotizacion) : super(db: FakeFirebaseFirestore());
  final QuoteRequest cotizacion;

  @override
  Stream<QuoteRequest?> observar(String id) => Stream.value(cotizacion);

  @override
  Stream<List<QuoteEvent>> observarEventos(String id) => Stream.value(const <QuoteEvent>[]);
}

// ---------------------------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------------------------

Map<String, dynamic> _solicitudMap([Map<String, dynamic> extra = const {}]) => {
      'compradorId': 'comp',
      'sellerId': 'vend',
      'coffeeLotId': 'lote1',
      'estado': 'aceptada',
      'compradorNombre': 'Compradora',
      'compradorCiudad': 'Medellín',
      'compradorTipo': 'tostador',
      'sellerNombre': 'Finca X',
      'loteNombre': 'Café Y',
      'lotePrecioCOP': 32000,
      'loteUnidad': 'kg',
      ...extra,
    };

Map<String, dynamic> _cotizacionMap([Map<String, dynamic> extra = const {}]) => {
      'interestRequestId': 'comp_lote1',
      'compradorId': 'comp',
      'sellerId': 'vend',
      'coffeeLotId': 'lote1',
      'cantidad': 50,
      'unidad': 'kg',
      'estado': 'ofertaEnviada',
      'compradorNombre': 'Compradora',
      'sellerNombre': 'Finca X',
      'loteNombre': 'Café Y',
      ...extra,
    };

AppUser _usuario({CuentaEstado estado = CuentaEstado.activa, DateTime? solicitada, DateTime? programada}) => AppUser(
      uid: 'ana',
      email: 'ana@x.co',
      nombre: 'Ana',
      rol: UserRole.vendedor,
      onboardingCompleto: true,
      cuentaEstado: estado,
      eliminacionSolicitadaAt: solicitada,
      eliminacionProgramadaAt: programada,
    );

final _compradora = AppUser(uid: 'comp', email: 'comp@x.co', nombre: 'Compradora', rol: UserRole.comprador, onboardingCompleto: true);

final _mensajes = [
  ChatMessage(id: 'm1', chatId: 'comp_lote1', senderId: 'comp', texto: 'Hola, ¿sigue disponible el lote?', timestamp: DateTime(2026, 11, 10, 9, 30)),
  ChatMessage(id: 'm2', chatId: 'comp_lote1', senderId: 'vend', texto: 'Sí, tenemos 200 kg.', timestamp: DateTime(2026, 11, 10, 9, 41)),
];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  // -------------------------------------------------------------------------------------------
  group('CuentaEstado: «eliminando»', () {
    test('se reconoce de forma explícita y es distinto de «eliminacionPendiente»', () {
      expect(leerCuentaEstado('eliminando'), CuentaEstado.eliminando);
      final u = AppUser.fromMap('ana', {'email': 'ana@x.co', 'nombre': 'Ana', 'rol': 'vendedor', 'onboardingCompleto': true, 'cuentaEstado': 'eliminando'});
      expect(u.cuentaEstado, CuentaEstado.eliminando);
      expect(u.eliminando, isTrue);
      expect(u.eliminacionPendiente, isFalse);
      expect(u.cuentaActiva, isFalse);
      expect(u.operacionesBloqueadas, isTrue);
    });

    test('los estados desconocidos siguen fallando de forma segura (nunca «activa»)', () {
      for (final raro in ['ELIMINANDO', 'Eliminando', 'eliminada', '', 'otraCosa', 7, true, <String>[]]) {
        expect(leerCuentaEstado(raro), CuentaEstado.desconocida, reason: '$raro');
        final u = AppUser.fromMap('ana', {'email': 'ana@x.co', 'nombre': 'Ana', 'rol': 'vendedor', 'onboardingCompleto': true, 'cuentaEstado': raro});
        expect(u.cuentaActiva, isFalse, reason: '$raro');
        expect(u.operacionesBloqueadas, isTrue, reason: '$raro');
      }
    });

    test('«activa», el campo ausente y «eliminacionPendiente» conservan su significado', () {
      expect(leerCuentaEstado(null), CuentaEstado.activa);
      expect(leerCuentaEstado('activa'), CuentaEstado.activa);
      expect(leerCuentaEstado('eliminacionPendiente'), CuentaEstado.eliminacionPendiente);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Mi cuenta con la cuenta «eliminando»', () {
    final programada = DateTime(2026, 11, 29, 17, 30);
    final solicitada = DateTime(2026, 11, 14, 17, 30);

    Future<void> montar(WidgetTester tester, Widget seccion) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: SingleChildScrollView(child: seccion))));
    }

    AccountDeletionSection seccion(AppUser u) => AccountDeletionSection(
          usuario: u,
          onSolicitar: (_) async => throw StateError('no debe llamarse'),
          onCancelar: (_) async => throw StateError('no debe llamarse'),
        );

    testWidgets('explica que el borrado definitivo está en proceso y NO ofrece cancelar ni solicitar', (tester) async {
      await montar(tester, seccion(_usuario(estado: CuentaEstado.eliminando, solicitada: solicitada, programada: programada)));
      expect(find.byKey(const ValueKey('tarjeta_cuenta_eliminando')), findsOneWidget);
      expect(find.textContaining('eliminación definitiva'), findsWidgets);
      expect(find.byKey(const ValueKey('boton_cancelar_eliminacion')), findsNothing);
      expect(find.byKey(const ValueKey('boton_eliminar_cuenta')), findsNothing);
      expect(find.text('Cancelar solicitud'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byKey(const ValueKey('tarjeta_cuenta_desconocida')), findsNothing);
      expect(find.byKey(const ValueKey('tarjeta_eliminacion_cuenta')), findsNothing);
    });

    testWidgets('«eliminacionPendiente» sigue con su plazo y su botón «Cancelar solicitud»', (tester) async {
      await montar(tester, seccion(_usuario(estado: CuentaEstado.eliminacionPendiente, solicitada: solicitada, programada: programada)));
      expect(find.byKey(const ValueKey('tarjeta_eliminacion_cuenta')), findsOneWidget);
      expect(find.byKey(const ValueKey('boton_cancelar_eliminacion')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarjeta_cuenta_eliminando')), findsNothing);
    });

    testWidgets('«activa» sigue ofreciendo «Eliminar mi cuenta»', (tester) async {
      await montar(tester, seccion(_usuario()));
      expect(find.byKey(const ValueKey('boton_eliminar_cuenta')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarjeta_cuenta_eliminando')), findsNothing);
    });

    testWidgets('un estado desconocido sigue mostrando el aviso conservador, no la tarjeta de «eliminando»', (tester) async {
      await montar(tester, seccion(_usuario(estado: CuentaEstado.desconocida)));
      expect(find.byKey(const ValueKey('tarjeta_cuenta_desconocida')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarjeta_cuenta_eliminando')), findsNothing);
    });

    testWidgets('avisarSiCuentaBloqueada: con «eliminando» bloquea y NO manda a cancelar en «Mi cuenta»', (tester) async {
      bool? resultado;
      await tester.pumpWidget(ChangeNotifierProvider<SessionProvider>.value(
        value: _SesionFalsa(_usuario(estado: CuentaEstado.eliminando), bloqueada: true),
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (context) => ElevatedButton(onPressed: () => resultado = avisarSiCuentaBloqueada(context), child: const Text('Enviar solicitud')))),
        ),
      ));
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pump();
      expect(resultado, isTrue);
      expect(find.text(mensajeCuentaEliminando), findsOneWidget);
      expect(find.text(mensajeCuentaBloqueada), findsNothing);
      expect(mensajeCuentaEliminando, isNot(contains('cancelar')));
    });

    testWidgets('avisarSiCuentaBloqueada: con «eliminacionPendiente» conserva el mensaje de siempre', (tester) async {
      bool? resultado;
      await tester.pumpWidget(ChangeNotifierProvider<SessionProvider>.value(
        value: _SesionFalsa(_usuario(estado: CuentaEstado.eliminacionPendiente), bloqueada: true),
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (context) => ElevatedButton(onPressed: () => resultado = avisarSiCuentaBloqueada(context), child: const Text('Enviar solicitud')))),
        ),
      ));
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pump();
      expect(resultado, isTrue);
      expect(find.text(mensajeCuentaBloqueada), findsOneWidget);
      expect(find.text(mensajeCuentaEliminando), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Documentos históricos sin los marcadores (comportamiento exactamente el actual)', () {
    test('InterestRequest: sin marcadores los nombres, la ciudad y el tipo salen tal cual', () {
      final s = InterestRequest.fromMap('comp_lote1', _solicitudMap());
      expect(s.compradorEliminado, isFalse);
      expect(s.sellerEliminado, isFalse);
      expect(s.anonimizadoEn, isNull);
      expect(s.estadoDesconocido, isFalse);
      expect(s.compradorNombreVisible, 'Compradora');
      expect(s.sellerNombreVisible, 'Finca X');
      expect(s.compradorCiudadVisible, 'Medellín');
      expect(s.compradorTipoVisible, 'tostador');
      expect(s.nombreContraparte('comp'), 'Finca X');
      expect(s.nombreContraparte('vend'), 'Compradora');
      expect(s.nombreSiContraparteEliminada('comp'), isNull);
      expect(s.nombreSiContraparteEliminada('vend'), isNull);
      expect(s.esConexion, isTrue);
    });

    test('QuoteRequest: sin marcadores los nombres salen tal cual', () {
      final q = QuoteRequest.fromMap('q1', _cotizacionMap());
      expect(q.compradorEliminado, isFalse);
      expect(q.sellerEliminado, isFalse);
      expect(q.anonimizadoEn, isNull);
      expect(q.estadoDesconocido, isFalse);
      expect(q.compradorNombreVisible, 'Compradora');
      expect(q.sellerNombreVisible, 'Finca X');
      expect(q.estado, EstadoCotizacion.ofertaEnviada);
    });

    test('un marcador que no es el booleano true (null, false, texto, número) NO cuenta como eliminado', () {
      for (final raro in [null, false, 'true', 'sí', 1, 0, <String, dynamic>{}]) {
        final s = InterestRequest.fromMap('x', _solicitudMap({'compradorEliminado': raro, 'sellerEliminado': raro}));
        expect(s.compradorEliminado, isFalse, reason: '$raro');
        expect(s.sellerEliminado, isFalse, reason: '$raro');
        expect(s.compradorNombreVisible, 'Compradora', reason: '$raro');
        final q = QuoteRequest.fromMap('q', _cotizacionMap({'compradorEliminado': raro, 'sellerEliminado': raro}));
        expect(q.compradorEliminado, isFalse, reason: '$raro');
        expect(q.sellerEliminado, isFalse, reason: '$raro');
      }
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Contrapartes eliminadas: lectura de marcadores', () {
    test('comprador eliminado: «Cuenta eliminada», sin ciudad ni tipo; el vendedor y todo lo demás intactos', () {
      final fecha = DateTime.utc(2026, 12, 1, 8);
      final s = InterestRequest.fromMap('comp_lote1', _solicitudMap({'compradorEliminado': true, 'anonimizadoEn': Timestamp.fromDate(fecha)}));
      expect(s.compradorEliminado, isTrue);
      expect(s.sellerEliminado, isFalse);
      expect(s.anonimizadoEn!.toUtc(), fecha);
      expect(nombreCuentaEliminada, 'Cuenta eliminada');
      expect(s.compradorNombreVisible, 'Cuenta eliminada');
      expect(s.compradorCiudadVisible, isNull);
      expect(s.compradorTipoVisible, isNull);
      expect(s.sellerNombreVisible, 'Finca X');
      expect(s.nombreContraparte('vend'), 'Cuenta eliminada');
      expect(s.nombreSiContraparteEliminada('vend'), 'Cuenta eliminada');
      expect(s.nombreSiContraparteEliminada('comp'), isNull);
      // Datos técnicos y comerciales intactos (los valores crudos no se tocan).
      expect(s.compradorNombre, 'Compradora');
      expect(s.compradorId, 'comp');
      expect(s.sellerId, 'vend');
      expect(s.id, 'comp_lote1');
      expect(s.estado, EstadoSolicitud.aceptada);
      expect(s.lotePrecioCOP, 32000);
    });

    test('vendedor eliminado: «Cuenta eliminada»; el comprador intacto', () {
      final s = InterestRequest.fromMap('comp_lote1', _solicitudMap({'sellerEliminado': true}));
      expect(s.sellerNombreVisible, 'Cuenta eliminada');
      expect(s.compradorNombreVisible, 'Compradora');
      expect(s.compradorCiudadVisible, 'Medellín');
      expect(s.nombreContraparte('comp'), 'Cuenta eliminada');
      expect(s.nombreSiContraparteEliminada('comp'), 'Cuenta eliminada');
      expect(s.nombreSiContraparteEliminada('vend'), isNull);
      expect(s.sellerNombre, 'Finca X');
      expect(s.esConexion, isTrue, reason: 'el estado no cambia: el chat aceptado sigue siendo una conexión');
    });

    test('cotización: nombre visible de cada parte y valores crudos, importes y estado intactos', () {
      final q = QuoteRequest.fromMap('q1', _cotizacionMap({
        'sellerEliminado': true,
        'compradorEliminado': true,
        'oferta': {
          'precioUnitarioCOP': 20000,
          'unidadPrecio': 'kg',
          'subtotalCOP': 1000000,
          'envioCOP': 0,
          'totalCOP': 1000000,
          'tiempoEntrega': '5 días',
        },
      }));
      expect(q.compradorNombreVisible, 'Cuenta eliminada');
      expect(q.sellerNombreVisible, 'Cuenta eliminada');
      expect(q.compradorNombre, 'Compradora');
      expect(q.sellerNombre, 'Finca X');
      expect(q.compradorId, 'comp');
      expect(q.sellerId, 'vend');
      expect(q.estado, EstadoCotizacion.ofertaEnviada);
      expect(q.cantidad, 50);
      expect(q.oferta!.totalCOP, 1000000);
    });

    test('los marcadores son solo de lectura: no entran en lo que la app escribe', () {
      final s = InterestRequest.fromMap('comp_lote1', _solicitudMap({'compradorEliminado': true, 'sellerEliminado': true}));
      for (final k in ['compradorEliminado', 'sellerEliminado', 'anonimizadoEn']) {
        expect(s.toCreateMap().containsKey(k), isFalse, reason: k);
      }
      final q = QuoteRequest.fromMap('q1', _cotizacionMap({'compradorEliminado': true, 'sellerEliminado': true}));
      for (final k in ['compradorEliminado', 'sellerEliminado', 'anonimizadoEn']) {
        expect(q.toCreateMap().containsKey(k), isFalse, reason: k);
      }
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Estados comerciales desconocidos: valor de respaldo conservado, pero nunca como acción abierta', () {
    test('InterestRequest: el respaldo sigue siendo «pendiente», pero se marca desconocido y no es pendiente abierta ni conexión', () {
      final s = InterestRequest.fromMap('x', _solicitudMap({'estado': 'cerradaPorEliminacion'}));
      expect(s.estado, EstadoSolicitud.pendiente, reason: 'valor de respaldo existente');
      expect(s.estadoDesconocido, isTrue);
      expect(s.esPendienteAbierta, isFalse);
      expect(s.esConexion, isFalse);
      final conocida = InterestRequest.fromMap('x', _solicitudMap({'estado': 'pendiente'}));
      expect(conocida.estadoDesconocido, isFalse);
      expect(conocida.esPendienteAbierta, isTrue);
    });

    test('QuoteRequest: el respaldo sigue siendo «solicitudPendiente», pero se marca desconocido', () {
      final q = QuoteRequest.fromMap('x', _cotizacionMap({'estado': 'cerradaPorEliminacion'}));
      expect(q.estado, EstadoCotizacion.solicitudPendiente, reason: 'valor de respaldo existente');
      expect(q.estadoDesconocido, isTrue);
      expect(QuoteRequest.fromMap('x', _cotizacionMap()).estadoDesconocido, isFalse);
    });

    test('cotizacionRequiereAccion es falso para ambos lados con un estado desconocido, y no cambia con los conocidos', () {
      final desconocida = QuoteRequest.fromMap('x', _cotizacionMap({'estado': 'cerradaPorEliminacion'}));
      expect(cotizacionRequiereAccion(desconocida, verComoVendedor: true), isFalse);
      expect(cotizacionRequiereAccion(desconocida, verComoVendedor: false), isFalse);
      final pendiente = QuoteRequest.fromMap('x', _cotizacionMap({'estado': 'solicitudPendiente'}));
      expect(cotizacionRequiereAccion(pendiente, verComoVendedor: true), isTrue);
      final oferta = QuoteRequest.fromMap('x', _cotizacionMap({'estado': 'ofertaEnviada', 'oferta': {'precioUnitarioCOP': 1, 'unidadPrecio': 'kg', 'subtotalCOP': 1, 'envioCOP': 0, 'totalCOP': 1, 'tiempoEntrega': '1 día', 'vigenciaHasta': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3)))}}));
      expect(cotizacionRequiereAccion(oferta, verComoVendedor: false), isTrue);
    });

    test('QuoteRepository: ninguna transición parte de un estado desconocido y el documento no cambia', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('quotes').doc('q1').set(_cotizacionMap({'estado': 'cerradaPorEliminacion'}));
      final repo = QuoteRepository(db: db);
      await expectLater(
        repo.cancelar(quoteId: 'q1', compradorUid: 'comp'),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.transicionInvalida)),
      );
      final doc = await db.collection('quotes').doc('q1').get();
      expect(doc.data()!['estado'], 'cerradaPorEliminacion');
      expect((await db.collection('quotes').doc('q1').collection('events').get()).docs, isEmpty);
    });

    test('InterestRequestRepository.responder: un estado desconocido no se puede aceptar ni rechazar', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('interestRequests').doc('comp_lote1').set(_solicitudMap({'estado': 'cerradaPorEliminacion'}));
      final repo = InterestRequestRepository(db: db);
      for (final aceptar in [true, false]) {
        await expectLater(repo.responder('comp_lote1', aceptar: aceptar), throwsA(isA<RepoException>()));
      }
      expect((await db.collection('interestRequests').doc('comp_lote1').get()).data()!['estado'], 'cerradaPorEliminacion');
    });

    test('el flujo normal no cambia: una solicitud pendiente conocida se acepta', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('interestRequests').doc('comp_lote1').set(_solicitudMap({'estado': 'pendiente'}));
      await InterestRequestRepository(db: db).responder('comp_lote1', aceptar: true);
      expect((await db.collection('interestRequests').doc('comp_lote1').get()).data()!['estado'], 'aceptada');
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Pantallas con una contraparte eliminada', () {
    void pantalla(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> montarChat(WidgetTester tester, InterestRequest conexion, {AppUser? usuario, String otroNombre = 'Finca X'}) async {
      pantalla(tester);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: _SesionFalsa(usuario ?? _compradora)),
          Provider<PushCoordinator>.value(value: _PushFalso()),
          Provider<InterestRequestRepository>.value(value: _ConexionesFalsas(conexion)),
          Provider<ChatRepository>.value(value: _ChatsFalso(_mensajes)),
          Provider<CoffeeLotRepository>.value(value: CoffeeLotRepository(db: FakeFirebaseFirestore())),
          Provider<QuoteRepository>.value(value: QuoteRepository(db: FakeFirebaseFirestore())),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: ChatScreen(interestRequestId: 'comp_lote1', otroNombre: otroNombre)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('chat aceptado con el vendedor eliminado: sigue legible, el encabezado dice «Cuenta eliminada» y el campo queda bloqueado', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap({'sellerEliminado': true}));
      await montarChat(tester, conexion);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.text('Finca X'), findsNothing);
      expect(find.text('Chat no disponible'), findsNothing);
      // Con la otra cuenta eliminada el chat es solo historial: aviso permanente y campo deshabilitado
      // (el detalle y el borrador se prueban en etapa7_0_ajustes_finales_test.dart).
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('chat visto por el vendedor con el comprador eliminado', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap({'compradorEliminado': true}));
      final vendedor = AppUser(uid: 'vend', email: 'vend@x.co', nombre: 'Finca X', rol: UserRole.vendedor, onboardingCompleto: true);
      await montarChat(tester, conexion, usuario: vendedor, otroNombre: 'Compradora');
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.text('Compradora'), findsNothing);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
    });

    testWidgets('chat sin marcadores: el encabezado conserva el nombre de siempre', (tester) async {
      await montarChat(tester, InterestRequest.fromMap('comp_lote1', _solicitudMap()));
      expect(find.text('Finca X'), findsOneWidget);
      expect(find.text('Cuenta eliminada'), findsNothing);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
    });

    testWidgets('QuoteCard: identifica a la otra parte eliminada sin tocar importes ni estado', (tester) async {
      pantalla(tester);
      final q = QuoteRequest.fromMap('q1', _cotizacionMap({
        'sellerEliminado': true,
        'oferta': {'precioUnitarioCOP': 20000, 'unidadPrecio': 'kg', 'subtotalCOP': 1000000, 'envioCOP': 0, 'totalCOP': 1000000, 'tiempoEntrega': '5 días'},
      }));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: QuoteCard(cotizacion: q, verComoVendedor: false, onTap: () {})),
      ));
      expect(find.text('Cuenta eliminada'), findsOneWidget);
      expect(find.text('Finca X'), findsNothing);
      expect(find.textContaining(formatCOP(1000000)), findsOneWidget);
      expect(find.text('Café Y'), findsOneWidget);
    });

    testWidgets('QuoteCard: sin marcadores muestra el nombre como siempre', (tester) async {
      pantalla(tester);
      final q = QuoteRequest.fromMap('q1', _cotizacionMap());
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: QuoteCard(cotizacion: q, verComoVendedor: true, onTap: () {})),
      ));
      expect(find.text('Compradora'), findsOneWidget);
      expect(find.text('Cuenta eliminada'), findsNothing);
    });

    testWidgets('detalle de cotización: «Partes» y la contraparte muestran «Cuenta eliminada»; importes y cantidad intactos', (tester) async {
      pantalla(tester);
      final q = QuoteRequest.fromMap('q1', _cotizacionMap({
        'sellerEliminado': true,
        'oferta': {
          'precioUnitarioCOP': 20000,
          'unidadPrecio': 'kg',
          'subtotalCOP': 1000000,
          'envioCOP': 0,
          'totalCOP': 1000000,
          'tiempoEntrega': '5 días',
          'vigenciaHasta': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
        },
      }));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: _SesionFalsa(_compradora)),
          Provider<PushCoordinator>.value(value: _PushFalso()),
          Provider<InterestRequestRepository>.value(value: InterestRequestRepository(db: FakeFirebaseFirestore())),
          Provider<ChatRepository>.value(value: ChatRepository(db: FakeFirebaseFirestore())),
          Provider<CoffeeLotRepository>.value(value: CoffeeLotRepository(db: FakeFirebaseFirestore())),
          Provider<QuoteRepository>.value(value: _CotizacionesFalsas(q)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const QuoteDetailScreen(quoteId: 'q1')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.text('Finca X'), findsNothing);
      expect(find.text('Compradora (tú)'), findsOneWidget);
      expect(find.textContaining('50 kg'), findsWidgets);
      expect(find.textContaining(formatCOP(1000000)), findsWidgets);
    });
  });
}
