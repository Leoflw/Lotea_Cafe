// Etapa 7.0 — ajustes finales: (1) chat de solo consulta PERMANENTE cuando la otra persona eliminó su
// cuenta; (2) «Estado no reconocido» en lugar del valor de respaldo de los enums.
// Solo lectura y presentación: no se escribe ningún marcador ni se cambia ningún estado.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/chat_message.dart';
import 'package:lotea_cafe/models/interest_request.dart';
import 'package:lotea_cafe/models/quote_request.dart';
import 'package:lotea_cafe/repositories/chat_repository.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/favorite_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';
import 'package:lotea_cafe/repositories/quote_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/screens/chat/chat_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_detail_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_widgets.dart';
import 'package:lotea_cafe/screens/requests/my_requests_screen.dart';
import 'package:lotea_cafe/services/push_navigation.dart';
import 'package:lotea_cafe/state/activity_provider.dart';
import 'package:lotea_cafe/state/session_provider.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/utils/negociacion_restringida.dart';
import 'package:lotea_cafe/widgets/status_pill.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------------------------
// Dobles de prueba (ninguno toca Firebase real).
// ---------------------------------------------------------------------------------------------

class _SesionFalsa extends ChangeNotifier implements SessionProvider {
  _SesionFalsa(this._usuario);
  final AppUser _usuario;

  @override
  AppUser? get usuario => _usuario;

  @override
  SessionStatus get status => SessionStatus.listo;

  @override
  bool get operacionesBloqueadas => false;

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

/// Emite primero [antes] y, cuando se abre la compuerta, [despues] (la contraparte elimina su cuenta con el chat abierto).
class _ConexionesEnDosTiempos extends InterestRequestRepository {
  _ConexionesEnDosTiempos(this.antes, this.despues) : super(db: FakeFirebaseFirestore());
  final InterestRequest antes;
  final InterestRequest despues;
  final Completer<void> compuerta = Completer<void>();

  @override
  Stream<InterestRequest?> observar(String id) async* {
    yield antes;
    await compuerta.future;
    yield despues;
  }
}

class _ChatsFalso extends ChatRepository {
  _ChatsFalso(this.mensajes, {this.falla}) : super(db: FakeFirebaseFirestore());
  final List<ChatMessage> mensajes;
  final Object? falla;
  int intentos = 0;

  @override
  Stream<List<ChatMessage>> observar(String chatId) => Stream.value(mensajes);

  @override
  Future<void> enviar({required String chatId, required String mensajeId, required String senderId, required String texto}) async {
    intentos++;
    final f = falla;
    if (f != null) throw f;
  }
}

class _CotizacionesFalsas extends QuoteRepository {
  _CotizacionesFalsas(this.cotizacion) : super(db: FakeFirebaseFirestore());
  final QuoteRequest cotizacion;

  @override
  Stream<QuoteRequest?> observar(String id) => Stream.value(cotizacion);

  @override
  Stream<List<QuoteEvent>> observarEventos(String id) => Stream.value(const <QuoteEvent>[]);
}

RepoException _rechazoDePermisos() => RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));

// ---------------------------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------------------------

Map<String, dynamic> _solicitudMap([Map<String, dynamic> extra = const {}]) => {
      'compradorId': 'comp',
      'sellerId': 'vend',
      'coffeeLotId': 'lote1',
      'estado': 'aceptada',
      'compradorNombre': 'Compradora',
      'sellerNombre': 'Finca X',
      'loteNombre': 'Café Y',
      'lotePrecioCOP': 32000,
      'loteUnidad': 'kg',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
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
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
      ...extra,
    };

Map<String, dynamic> _oferta({bool vigente = true}) => {
      'precioUnitarioCOP': 20000,
      'unidadPrecio': 'kg',
      'subtotalCOP': 1000000,
      'envioCOP': 0,
      'totalCOP': 1000000,
      'tiempoEntrega': '5 días',
      if (vigente) 'vigenciaHasta': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
    };

final _compradora = AppUser(uid: 'comp', email: 'comp@x.co', nombre: 'Compradora', rol: UserRole.comprador, onboardingCompleto: true);
final _vendedor = AppUser(uid: 'vend', email: 'vend@x.co', nombre: 'Finca X', rol: UserRole.vendedor, onboardingCompleto: true);

final _mensajes = [
  ChatMessage(id: 'm1', chatId: 'comp_lote1', senderId: 'comp', texto: 'Hola, ¿sigue disponible el lote?', timestamp: DateTime(2026, 11, 10, 9, 30)),
  ChatMessage(id: 'm2', chatId: 'comp_lote1', senderId: 'vend', texto: 'Sí, tenemos 200 kg.', timestamp: DateTime(2026, 11, 10, 9, 41)),
];

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  void pantalla(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> montar(
    WidgetTester tester,
    Widget home, {
    AppUser? usuario,
    InterestRequestRepository? conexiones,
    ChatRepository? chats,
    QuoteRepository? cotizaciones,
    ActivityProvider? actividad,
  }) async {
    pantalla(tester);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: _SesionFalsa(usuario ?? _compradora)),
        if (actividad != null) ChangeNotifierProvider<ActivityProvider>.value(value: actividad),
        Provider<PushCoordinator>.value(value: _PushFalso()),
        Provider<InterestRequestRepository>.value(value: conexiones ?? InterestRequestRepository(db: FakeFirebaseFirestore())),
        Provider<ChatRepository>.value(value: chats ?? _ChatsFalso(_mensajes)),
        Provider<CoffeeLotRepository>.value(value: CoffeeLotRepository(db: FakeFirebaseFirestore())),
        Provider<QuoteRepository>.value(value: cotizaciones ?? QuoteRepository(db: FakeFirebaseFirestore())),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await tester.pumpAndSettle();
  }

  ChatScreen chat(String otroNombre) => ChatScreen(interestRequestId: 'comp_lote1', otroNombre: otroNombre);

  // -------------------------------------------------------------------------------------------
  group('Chat de solo consulta permanente (la otra persona eliminó su cuenta)', () {
    void esConsultaPermanente(WidgetTester tester) {
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsOneWidget);
      expect(find.text(mensajeChatContraparteEliminada), findsOneWidget);
      expect(mensajeChatContraparteEliminada, 'Esta cuenta fue eliminada. La conversación se conserva únicamente como historial.');
      // Campo y envío deshabilitados.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send_rounded)).onPressed, isNull);
      // No es una restricción temporal: ni «Volver a intentar» ni el aviso temporal.
      expect(find.byKey(const ValueKey('chat_volver_a_intentar')), findsNothing);
      expect(find.text('Volver a intentar'), findsNothing);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.text(mensajeChatSoloConsulta), findsNothing);
      // Historial intacto.
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
    }

    testWidgets('comprador eliminado (lo ve el vendedor): historial visible, campo bloqueado y aviso permanente', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap({'compradorEliminado': true}));
      final chats = _ChatsFalso(_mensajes);
      await montar(tester, chat('Compradora'), usuario: _vendedor, conexiones: _ConexionesFalsas(conexion), chats: chats);
      esConsultaPermanente(tester);
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.text('Compradora'), findsNothing);
      await tester.tap(find.byTooltip('Enviar'), warnIfMissed: false);
      await tester.pump();
      expect(chats.intentos, 0, reason: 'no se intenta enviar nada');
    });

    testWidgets('vendedor eliminado (lo ve la compradora): mismo comportamiento', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap({'sellerEliminado': true}));
      final chats = _ChatsFalso(_mensajes);
      await montar(tester, chat('Finca X'), usuario: _compradora, conexiones: _ConexionesFalsas(conexion), chats: chats);
      esConsultaPermanente(tester);
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.text('Finca X'), findsNothing);
      await tester.tap(find.byTooltip('Enviar'), warnIfMissed: false);
      await tester.pump();
      expect(chats.intentos, 0);
    });

    testWidgets('el bloqueo no espera a Firestore y el borrador escrito antes NO se elimina', (tester) async {
      final antes = InterestRequest.fromMap('comp_lote1', _solicitudMap());
      final despues = InterestRequest.fromMap('comp_lote1', _solicitudMap({'sellerEliminado': true}));
      final conexiones = _ConexionesEnDosTiempos(antes, despues);
      final chats = _ChatsFalso(_mensajes);
      await montar(tester, chat('Finca X'), usuario: _compradora, conexiones: conexiones, chats: chats);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsNothing);

      await tester.enterText(find.byType(TextField), 'Quería pedir 100 kg');
      await tester.pump();

      conexiones.compuerta.complete(); // llega el marcador mientras el chat está abierto
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Quería pedir 100 kg'), findsOneWidget, reason: 'el borrador sigue visible (solo lectura)');
      expect(find.text('Cuenta eliminada'), findsWidgets);
      expect(find.byKey(const ValueKey('chat_volver_a_intentar')), findsNothing);
      expect(chats.intentos, 0, reason: 'no hubo ningún rechazo de Firestore: el estado salió del marcador');
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
    });

    testWidgets('el marcador del PROPIO usuario en un documento histórico no bloquea el chat', (tester) async {
      // Comprador visto por sí mismo con compradorEliminado = true: no es «la otra persona».
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap({'compradorEliminado': true}));
      await montar(tester, chat('Finca X'), usuario: _compradora, conexiones: _ConexionesFalsas(conexion));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsNothing);
      expect(find.text('Finca X'), findsOneWidget);
    });

    testWidgets('sin marcadores el chat conserva su comportamiento normal', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap());
      await montar(tester, chat('Finca X'), conexiones: _ConexionesFalsas(conexion));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send_rounded)).onPressed, isNotNull);
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsNothing);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.text('Finca X'), findsOneWidget);
    });

    testWidgets('un permission-denied SIN marcador sigue usando el modo de consulta temporal (con «Volver a intentar»)', (tester) async {
      final conexion = InterestRequest.fromMap('comp_lote1', _solicitudMap());
      final chats = _ChatsFalso(_mensajes, falla: _rechazoDePermisos());
      await montar(tester, chat('Finca X'), conexiones: _ConexionesFalsas(conexion), chats: chats);
      await tester.enterText(find.byType(TextField), 'Quiero 100 kg');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(chats.intentos, 1);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_volver_a_intentar')), findsOneWidget);
      expect(find.text(mensajeChatSoloConsulta), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_cuenta_eliminada')), findsNothing);
      expect(find.text(mensajeChatContraparteEliminada), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('«Estado no reconocido» (solicitudes)', () {
    testWidgets('el chip dice «Estado no reconocido» y no el valor de respaldo; los conocidos conservan su etiqueta', (tester) async {
      Future<void> chip(Widget w) => tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: w))));
      await chip(const RequestStatusChip(estado: EstadoSolicitud.pendiente, desconocido: true));
      expect(find.text('Estado no reconocido'), findsOneWidget);
      expect(find.text('Pendiente'), findsNothing);
      await chip(const RequestStatusChip(estado: EstadoSolicitud.pendiente));
      expect(find.text('Pendiente'), findsOneWidget);
      await chip(const RequestStatusChip(estado: EstadoSolicitud.aceptada));
      expect(find.text('Conexión comercial'), findsOneWidget);
      await chip(const RequestStatusChip(estado: EstadoSolicitud.rechazada));
      expect(find.text('Rechazada'), findsOneWidget);
      // El valor de respaldo interno del enum no cambió.
      expect(InterestRequest.fromMap('x', _solicitudMap({'estado': 'cerradaPorEliminacion'})).estado, EstadoSolicitud.pendiente);
    });

    testWidgets('«Mis solicitudes»: la solicitud desconocida muestra «Estado no reconocido», sin «Pendiente» ni «Esperando…»', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('interestRequests').doc('comp_a').set(_solicitudMap({'coffeeLotId': 'a', 'estado': 'pendiente', 'loteNombre': 'Lote conocido'}));
      await db.collection('interestRequests').doc('comp_b').set(_solicitudMap({'coffeeLotId': 'b', 'estado': 'cerradaPorEliminacion', 'loteNombre': 'Lote desconocido', 'createdAt': Timestamp.fromDate(DateTime(2026, 11, 11))}));
      final actividad = ActivityProvider(
        sellers: SellerRepository(db: db),
        lots: CoffeeLotRepository(db: db),
        requests: InterestRequestRepository(db: db),
        favorites: FavoriteRepository(db: db),
        quotes: QuoteRepository(db: db),
      );
      addTearDown(actividad.dispose);
      actividad.actualizarSesion(_SesionFalsa(_compradora));
      await montar(tester, const MyRequestsScreen(), actividad: actividad);
      await tester.pumpAndSettle();

      expect(find.text('Enviadas (2)'), findsOneWidget);
      expect(find.text('Estado no reconocido'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget, reason: 'solo la solicitud de estado conocido');
      expect(find.text('Esperando la respuesta del vendedor'), findsOneWidget, reason: 'solo la conocida');
      expect(find.text('Lote desconocido'), findsOneWidget);
      expect(find.text('Lote conocido'), findsOneWidget);
    });

    test('las solicitudes desconocidas no se cuentan como pendientes (vista del vendedor)', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('interestRequests').doc('comp_a').set(_solicitudMap({'coffeeLotId': 'a', 'estado': 'pendiente'}));
      await db.collection('interestRequests').doc('comp_b').set(_solicitudMap({'coffeeLotId': 'b', 'estado': 'cerradaPorEliminacion'}));
      await db.collection('interestRequests').doc('comp_c').set(_solicitudMap({'coffeeLotId': 'c', 'estado': 'rechazada'}));
      final actividad = ActivityProvider(
        sellers: SellerRepository(db: db),
        lots: CoffeeLotRepository(db: db),
        requests: InterestRequestRepository(db: db),
        favorites: FavoriteRepository(db: db),
        quotes: QuoteRepository(db: db),
      );
      addTearDown(actividad.dispose);
      actividad.actualizarSesion(_SesionFalsa(_vendedor));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(actividad.listaSolicitudes.length, 3);
      expect(actividad.pendientes.length, 1);
      expect(actividad.pendientes.single.id, 'comp_a');
      expect(actividad.conexiones, isEmpty);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('«Estado no reconocido» (cotizaciones)', () {
    testWidgets('QuoteCard: etiqueta «Estado no reconocido», sin «Requiere tu respuesta»; las conocidas igual que antes', (tester) async {
      pantalla(tester);
      Future<void> tarjeta(QuoteRequest q, {required bool vendedor}) => tester.pumpWidget(MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: QuoteCard(cotizacion: q, verComoVendedor: vendedor, onTap: () {})),
          ));
      final desconocida = QuoteRequest.fromMap('q1', _cotizacionMap({'estado': 'cerradaPorEliminacion'}));
      await tarjeta(desconocida, vendedor: true);
      expect(find.text('Estado no reconocido'), findsOneWidget);
      expect(find.text('Requiere tu respuesta'), findsNothing);
      expect(find.text(EstadoCotizacion.solicitudPendiente.corto), findsNothing, reason: 'no se muestra el valor de respaldo');
      // Conocida: etiqueta y aviso de siempre.
      final conocida = QuoteRequest.fromMap('q2', _cotizacionMap({'estado': 'solicitudPendiente'}));
      await tarjeta(conocida, vendedor: true);
      expect(find.text(EstadoCotizacion.solicitudPendiente.corto), findsOneWidget);
      expect(find.text('Requiere tu respuesta'), findsOneWidget);
      expect(find.text('Estado no reconocido'), findsNothing);
    });

    testWidgets('detalle de cotización desconocida: etiqueta, explicación y NINGUNA acción comercial (vendedor y comprador)', (tester) async {
      // Acciones COMERCIALES del detalle (etiquetas reales de quote_detail_screen.dart).
      const accionesComerciales = [
        'Enviar oferta',
        'Enviar nueva oferta',
        'Rechazar solicitud',
        'Aceptar oferta',
        'Solicitar ajuste',
        'Rechazar oferta',
        'Cancelar cotización',
      ];
      // Instrucciones de «próxima acción» que invitan a responder (vendedor y comprador).
      const instrucciones = [
        'Te toca responder: envía una oferta o rechaza la solicitud.',
        'El comprador pidió un ajuste. Envía una nueva oferta o rechaza la solicitud.',
        'Esperando la respuesta del comprador.',
        'Esperando la respuesta del vendedor.',
        'El vendedor te envió una oferta. Puedes aceptarla, pedir un ajuste o rechazarla.',
        'Pediste un ajuste. Esperando una nueva oferta del vendedor.',
      ];
      for (final usuario in [_vendedor, _compradora]) {
        final q = QuoteRequest.fromMap('q1', _cotizacionMap({'estado': 'cerradaPorEliminacion', 'oferta': _oferta()}));
        await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), usuario: usuario, cotizaciones: _CotizacionesFalsas(q));
        final quien = usuario.uid;
        // Se conserva la etiqueta y la explicación del estado no reconocido.
        expect(find.text('Estado no reconocido'), findsWidgets, reason: quien);
        expect(find.text(mensajeEstadoNoReconocido), findsOneWidget, reason: quien);
        // No hay ninguna acción comercial (ni como texto de botón ni como botón principal).
        for (final accion in accionesComerciales) {
          expect(find.text(accion), findsNothing, reason: '$quien: «$accion»');
        }
        expect(find.byType(ElevatedButton), findsNothing, reason: '$quien: acción comercial principal');
        // No aparecen las instrucciones para responder a una cotización.
        for (final texto in instrucciones) {
          expect(find.text(texto), findsNothing, reason: '$quien: «$texto»');
        }
        // «Abrir chat» es navegación al historial, no una acción comercial: se conserva.
        expect(find.text('Abrir chat'), findsOneWidget, reason: quien);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('detalle de una cotización conocida: conserva su texto y sus acciones', (tester) async {
      // Solicitud pendiente vista por el vendedor: «Te toca responder» y acción principal.
      final pendiente = QuoteRequest.fromMap('q1', _cotizacionMap({'estado': 'solicitudPendiente'}));
      await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), usuario: _vendedor, cotizaciones: _CotizacionesFalsas(pendiente));
      expect(find.text('Te toca responder: envía una oferta o rechaza la solicitud.'), findsOneWidget);
      expect(find.text(mensajeEstadoNoReconocido), findsNothing);
      expect(find.text('Estado no reconocido'), findsNothing);
      expect(find.byType(ElevatedButton), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      // Oferta vigente vista por el comprador: puede responder.
      final oferta = QuoteRequest.fromMap('q1', _cotizacionMap({'estado': 'ofertaEnviada', 'oferta': _oferta()}));
      await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), usuario: _compradora, cotizaciones: _CotizacionesFalsas(oferta));
      expect(find.text('El vendedor te envió una oferta. Puedes aceptarla, pedir un ajuste o rechazarla.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsWidgets);
    });

    test('las cotizaciones desconocidas no cuentan como «por responder»', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('quotes').doc('q1').set(_cotizacionMap({'estado': 'solicitudPendiente'}));
      await db.collection('quotes').doc('q2').set(_cotizacionMap({'estado': 'cerradaPorEliminacion'}));
      final actividad = ActivityProvider(
        sellers: SellerRepository(db: db),
        lots: CoffeeLotRepository(db: db),
        requests: InterestRequestRepository(db: db),
        favorites: FavoriteRepository(db: db),
        quotes: QuoteRepository(db: db),
      );
      addTearDown(actividad.dispose);
      actividad.actualizarSesion(_SesionFalsa(_vendedor));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(actividad.listaCotizaciones.length, 2);
      expect(actividad.cotizacionesPorResponder, 1);
    });
  });
}
