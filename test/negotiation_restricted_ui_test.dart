import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/chat_message.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/interest_request.dart';
import 'package:lotea_cafe/models/quote_request.dart';
import 'package:lotea_cafe/repositories/chat_repository.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';
import 'package:lotea_cafe/repositories/quote_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/screens/chat/chat_screen.dart';
import 'package:lotea_cafe/screens/coffee/coffee_lot_detail_screen.dart';
import 'package:lotea_cafe/screens/quotes/offer_form_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_detail_screen.dart';
import 'package:lotea_cafe/screens/quotes/quote_request_screen.dart';
import 'package:lotea_cafe/services/push_navigation.dart';
import 'package:lotea_cafe/state/session_provider.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/utils/format_utils.dart';
import 'package:lotea_cafe/utils/negociacion_restringida.dart';
import 'package:lotea_cafe/widgets/app_image.dart';
import 'package:lotea_cafe/widgets/cafe_no_disponible_view.dart';
import 'package:lotea_cafe/widgets/remote_view.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------------------------
// Dobles de prueba. Ninguno toca Firebase real. Las reglas de Firestore NO se ejecutan aquí: lo
// que se simula es que el servidor RECHAZA la operación (permission-denied), que es lo que la app
// recibe cuando la otra cuenta tiene una eliminación pendiente. Las reglas siguen cubiertas por
// rules-tests/account_lifecycle.rules.test.js (sin cambios).
// ---------------------------------------------------------------------------------------------

RepoException _rechazoDePermisos() => RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
RepoException _sinConexion() => RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

class _SesionFalsa extends ChangeNotifier implements SessionProvider {
  _SesionFalsa(this._usuario);
  final AppUser _usuario;

  @override
  AppUser? get usuario => _usuario;

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

class _ChatsFalso extends ChatRepository {
  _ChatsFalso(this.mensajes, {this.falla}) : super(db: FakeFirebaseFirestore());
  final List<ChatMessage> mensajes;
  Object? falla;
  int intentos = 0;

  @override
  Stream<List<ChatMessage>> observar(String chatId) => Stream.value(mensajes);

  @override
  Future<void> enviar({required String chatId, required String mensajeId, required String senderId, required String texto}) async {
    intentos++;
    final f = falla;
    if (f != null) throw f;
    // Solo se simula el éxito si no hay fallo; nunca se agrega a [mensajes] un envío rechazado.
  }
}

class _LotesFalsos extends CoffeeLotRepository {
  _LotesFalsos({this.error, this.lote}) : super(db: FakeFirebaseFirestore());
  final Object? error;
  final CoffeeLot? lote;

  @override
  Stream<CoffeeLot?> observar(String lotId) {
    final e = error;
    if (e != null) return Stream<CoffeeLot?>.error(e);
    return Stream<CoffeeLot?>.value(lote);
  }

  @override
  Future<CoffeeLot?> obtener(String lotId) async {
    final e = error;
    if (e != null) throw e;
    return lote;
  }
}

class _CotizacionesFalsas extends QuoteRepository {
  _CotizacionesFalsas(this.cotizacion, {this.falla}) : super(db: FakeFirebaseFirestore());
  final QuoteRequest cotizacion;
  Object? falla;
  final List<String> llamadas = [];

  Future<void> _intento(String nombre) async {
    llamadas.add(nombre);
    final f = falla;
    if (f != null) throw f;
  }

  @override
  Stream<QuoteRequest?> observar(String id) => Stream.value(cotizacion);

  @override
  Stream<List<QuoteEvent>> observarEventos(String id) => Stream.value(const <QuoteEvent>[]);

  @override
  Future<void> aceptarOferta({required String quoteId, required String compradorUid}) => _intento('aceptarOferta');

  @override
  Future<void> rechazarOferta({required String quoteId, required String compradorUid, String? motivo}) => _intento('rechazarOferta');

  @override
  Future<void> solicitarRevision({required String quoteId, required String compradorUid, required String comentario}) => _intento('solicitarRevision');

  @override
  Future<void> cancelar({required String quoteId, required String compradorUid}) => _intento('cancelar');

  @override
  Future<void> enviarOferta({
    required String quoteId,
    required String vendedorUid,
    required int precioUnitarioCOP,
    required int envioCOP,
    required String tiempoEntrega,
    DateTime? vigenciaHasta,
    String? condiciones,
    String? mensaje,
  }) =>
      _intento('enviarOferta');

  @override
  Future<QuoteRequest> crearSolicitud({
    required String quoteId,
    required InterestRequest conexion,
    required CoffeeLot lote,
    required String compradorUid,
    required double cantidad,
    required String unidad,
    String? lugarEntrega,
    String? comentario,
  }) async {
    await _intento('crearSolicitud');
    return cotizacion;
  }
}

const _conexion = InterestRequest(
  id: 'comp_lote1',
  compradorId: 'comp',
  sellerId: 'vend',
  coffeeLotId: 'lote1',
  estado: EstadoSolicitud.aceptada,
  compradorNombre: 'Compradora',
  sellerNombre: 'Finca X',
  loteNombre: 'Café Y',
  lotePrecioCOP: 32000,
  loteUnidad: 'kg',
);

final _mensajes = [
  ChatMessage(id: 'm1', chatId: 'comp_lote1', senderId: 'comp', texto: 'Hola, ¿sigue disponible el lote?', timestamp: DateTime(2026, 11, 10, 9, 30)),
  ChatMessage(id: 'm2', chatId: 'comp_lote1', senderId: 'vend', texto: 'Sí, tenemos 200 kg.', timestamp: DateTime(2026, 11, 10, 9, 41)),
];

const _cotizacion = QuoteRequest(
  id: 'q1',
  interestRequestId: 'comp_lote1',
  compradorId: 'comp',
  sellerId: 'vend',
  coffeeLotId: 'lote1',
  cantidad: 50,
  unidad: 'kg',
  estado: EstadoCotizacion.ofertaEnviada,
  oferta: QuoteOffer(precioUnitarioCOP: 20000, unidadPrecio: 'kg', subtotalCOP: 1000000, envioCOP: 0, totalCOP: 1000000, tiempoEntrega: '5 días'),
  compradorNombre: 'Compradora',
  sellerNombre: 'Finca X',
  loteNombre: 'Café Y',
);

final _compradora = AppUser(uid: 'comp', email: 'comp@x.co', nombre: 'Compradora', rol: UserRole.comprador, onboardingCompleto: true);
final _vendedor = AppUser(uid: 'vend', email: 'vend@x.co', nombre: 'Finca X', rol: UserRole.vendedor, onboardingCompleto: true);

const _solicitud = QuoteRequest(
  id: 'q2',
  interestRequestId: 'comp_lote1',
  compradorId: 'comp',
  sellerId: 'vend',
  coffeeLotId: 'lote1',
  cantidad: 50,
  unidad: 'kg',
  estado: EstadoCotizacion.solicitudPendiente,
  compradorNombre: 'Compradora',
  sellerNombre: 'Finca X',
  loteNombre: 'Café Y',
);

const _lote = CoffeeLot(id: 'lote1', sellerId: 'vend', nombre: 'Café Y', variedades: ['Castillo'], proceso: 'Lavado', precioCOP: 32000);

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
    ChatRepository? chats,
    CoffeeLotRepository? lotes,
    QuoteRepository? cotizaciones,
    AppUser? usuario,
  }) async {
    pantalla(tester);
    await tester.pumpWidget(MultiProvider(
      providers: [
        // SessionProvider es un ChangeNotifier (en main.dart va con ChangeNotifierProvider): un Provider
        // simple lo rechaza con Provider.debugCheckInvalidValueType, que se deja activo.
        ChangeNotifierProvider<SessionProvider>.value(value: _SesionFalsa(usuario ?? _compradora)),
        Provider<PushCoordinator>.value(value: _PushFalso()),
        Provider<InterestRequestRepository>.value(value: _ConexionesFalsas(_conexion)),
        Provider<ChatRepository>.value(value: chats ?? _ChatsFalso(_mensajes)),
        Provider<CoffeeLotRepository>.value(value: lotes ?? _LotesFalsos()),
        Provider<QuoteRepository>.value(value: cotizaciones ?? _CotizacionesFalsas(_cotizacion)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------------------------------
  group('esRechazoPorPermisos y textos', () {
    test('solo un rechazo de permisos que viene de Firestore cuenta', () {
      expect(esRechazoPorPermisos(_rechazoDePermisos()), isTrue);
      expect(esRechazoPorPermisos(const RepoException(RepoErrorKind.sinPermisos, 'No participas en esta cotización.')), isFalse, reason: 'chequeo local');
      expect(esRechazoPorPermisos(_sinConexion()), isFalse);
      expect(esRechazoPorPermisos(StateError('x')), isFalse);
    });

    test('los avisos no revelan a la contraparte que existe una eliminación de cuenta', () {
      final textos = [
        mensajeChatSoloConsulta,
        mensajeNegociacionRestringida('aceptar la oferta'),
        mensajeCotizacionSoloConsulta,
      ];
      for (final t in textos) {
        expect(t.toLowerCase(), isNot(contains('eliminaci')), reason: t);
        expect(t.toLowerCase(), isNot(contains('borrad')), reason: t);
        expect(t, isNot(contains('No tienes permiso')), reason: 'no es el mensaje genérico');
      }
      expect(mensajeNegociacionRestringida('cancelar la cotización'), contains('No se pudo cancelar la cotización.'));
    });

    test('LoteRespaldo toma solo datos de visualización de la conversación (sin fotos)', () {
      final r = LoteRespaldo.desdeConexion(_conexion);
      expect(r.nombre, 'Café Y');
      expect(r.vendedor, 'Finca X');
      expect(r.precioCOP, 32000);
      expect(r.unidad, 'kg');
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Chat en modo de consulta', () {
    testWidgets('antes de cualquier rechazo: historial visible y campo de escritura disponible', (tester) async {
      await montar(tester, const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X'));
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
    });

    testWidgets('rechazo de permisos: aviso comprensible, sin campo de envío, historial intacto y sin éxito falso', (tester) async {
      final chats = _ChatsFalso(_mensajes, falla: _rechazoDePermisos());
      await montar(tester, const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X'), chats: chats);

      await tester.enterText(find.byType(TextField), 'Quiero 100 kg');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(chats.intentos, 1);
      // Aviso contextual (no el genérico) y modo de consulta.
      expect(find.byType(SnackBar), findsNothing, reason: 'el aviso es el banner persistente; un SnackBar taparía «Volver a intentar»');
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsOneWidget);
      expect(find.text(mensajeChatSoloConsulta), findsOneWidget);
      // Sin campo de escritura ni botón de envío.
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Enviar'), findsNothing);
      // Historial intacto; el mensaje rechazado NO aparece como enviado.
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(find.text('Sí, tenemos 200 kg.'), findsOneWidget);
      expect(find.text('Quiero 100 kg'), findsNothing);
      expect(chats.mensajes.length, 2);
    });

    testWidgets('«Volver a intentar» restablece el campo de escritura', (tester) async {
      final chats = _ChatsFalso(_mensajes, falla: _rechazoDePermisos());
      await montar(tester, const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X'), chats: chats);
      await tester.enterText(find.byType(TextField), 'Hola');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      // Inmediatamente después del rechazo (sin esperar): ningún SnackBar, y el botón es alcanzable
      // (`hitTestable` falla si algo lo tapa) y tiene el aviso persistente encima.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsOneWidget);
      final volver = find.byKey(const ValueKey('chat_volver_a_intentar'));
      expect(volver.hitTestable(), findsOneWidget, reason: 'nada tapa «Volver a intentar»');

      await tester.tap(volver);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      // El borrador se conservó y el campo vuelve a funcionar: con el servidor ya sin rechazo, el reintento envía.
      expect(find.text('Hola'), findsOneWidget);
      chats.falla = null;
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(chats.intentos, 2);
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Hola'), findsNothing, reason: 'enviado: el campo se vació');
    });

    testWidgets('un fallo que NO es de permisos (sin conexión) no activa el modo de consulta y conserva el texto', (tester) async {
      final chats = _ChatsFalso(_mensajes, falla: _sinConexion());
      await montar(tester, const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X'), chats: chats);
      await tester.enterText(find.byType(TextField), 'Sigo aquí');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Sigo aquí'), findsOneWidget); // el texto sigue en el campo para reintentar
      expect(find.byType(SnackBar), findsOneWidget, reason: 'los errores que no son de permisos conservan su SnackBar estándar');
      expect(find.textContaining('Sin conexión'), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Café suspendido: pantalla de indisponibilidad', () {
    testWidgets('sin permiso de lectura: indisponibilidad, no error técnico, con datos guardados en solo lectura y sin imágenes', (tester) async {
      await montar(
        tester,
        CoffeeLotDetailScreen(coffeeLotId: 'lote1', respaldo: LoteRespaldo.desdeConexion(_conexion)),
        lotes: _LotesFalsos(error: _rechazoDePermisos()),
      );
      expect(find.text('Este café no está disponible'), findsOneWidget);
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.byKey(const ValueKey('cafe_respaldo')), findsOneWidget);
      expect(find.text('Café Y'), findsOneWidget);
      expect(find.text('Finca X'), findsOneWidget);
      expect(find.text(formatCOPPorUnidad(32000, 'kg')), findsOneWidget);
      // No se muestran ni se piden fotografías del café.
      expect(find.byType(AppImage), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('sin copia histórica: solo el mensaje de que el café ya no está disponible', (tester) async {
      await montar(tester, const CoffeeLotDetailScreen(coffeeLotId: 'lote1'), lotes: _LotesFalsos(error: _rechazoDePermisos()));
      expect(find.text('Este café no está disponible'), findsOneWidget);
      expect(find.byKey(const ValueKey('cafe_respaldo')), findsNothing);
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
    });

    testWidgets('café inexistente (documento nulo): misma pantalla, no «Café no encontrado»', (tester) async {
      await montar(tester, const CoffeeLotDetailScreen(coffeeLotId: 'lote1'), lotes: _LotesFalsos());
      expect(find.text('Este café no está disponible'), findsOneWidget);
      expect(find.text('Café no encontrado'), findsNothing);
    });

    testWidgets('un fallo de red NO se presenta como indisponibilidad: sigue el error recuperable', (tester) async {
      await montar(tester, const CoffeeLotDetailScreen(coffeeLotId: 'lote1'), lotes: _LotesFalsos(error: _sinConexion()));
      expect(find.text('Este café no está disponible'), findsNothing);
      expect(find.textContaining('Sin conexión'), findsWidgets);
    });

    testWidgets('desde el chat, «Ver café» abre la indisponibilidad con los datos guardados de la conversación', (tester) async {
      await montar(
        tester,
        const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X'),
        lotes: _LotesFalsos(error: _rechazoDePermisos()),
      );
      await tester.tap(find.text('Ver café'));
      await tester.pumpAndSettle();
      expect(find.text('Este café no está disponible'), findsOneWidget);
      expect(find.byKey(const ValueKey('cafe_respaldo')), findsOneWidget);
      expect(find.text(formatCOPPorUnidad(32000, 'kg')), findsOneWidget);
    });

    testWidgets('crear una cotización nueva sobre un café no legible: indisponibilidad, no error de permisos', (tester) async {
      await montar(tester, const QuoteRequestScreen(conexion: _conexion), lotes: _LotesFalsos(error: _rechazoDePermisos()));
      expect(find.byKey(const ValueKey('cotizar_cafe_no_disponible')), findsOneWidget);
      expect(find.text('Este café no está disponible por ahora'), findsOneWidget);
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
    });

    testWidgets('crear una cotización con el documento del café inexistente: misma indisponibilidad', (tester) async {
      await montar(tester, const QuoteRequestScreen(conexion: _conexion), lotes: _LotesFalsos());
      expect(find.byKey(const ValueKey('cotizar_cafe_no_disponible')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Cotizaciones en modo de consulta', () {
    Future<void> tocarConfirmar(WidgetTester tester, String boton) async {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(ElevatedButton, boton)));
      await tester.pumpAndSettle();
    }

    final acciones = <String, Future<void> Function(WidgetTester)>{
      'aceptar la oferta': (t) async {
        await t.tap(find.widgetWithText(ElevatedButton, 'Aceptar oferta'));
        await t.pumpAndSettle();
        await tocarConfirmar(t, 'Aceptar oferta');
      },
      'solicitar el ajuste': (t) async {
        await t.tap(find.widgetWithText(OutlinedButton, 'Solicitar ajuste'));
        await t.pumpAndSettle();
        await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Necesito otro precio');
        await t.pump();
        await tocarConfirmar(t, 'Enviar');
      },
      'rechazar la oferta': (t) async {
        await t.tap(find.widgetWithText(TextButton, 'Rechazar oferta'));
        await t.pumpAndSettle();
        await tocarConfirmar(t, 'Enviar');
      },
      'cancelar la cotización': (t) async {
        await t.tap(find.widgetWithText(TextButton, 'Cancelar cotización'));
        await t.pumpAndSettle();
        await tocarConfirmar(t, 'Sí, cancelar');
      },
    };
    const metodos = {
      'aceptar la oferta': 'aceptarOferta',
      'solicitar el ajuste': 'solicitarRevision',
      'rechazar la oferta': 'rechazarOferta',
      'cancelar la cotización': 'cancelar',
    };
    const exitos = ['Oferta aceptada', 'Ajuste solicitado', 'Oferta rechazada', 'Cotización cancelada'];

    for (final e in acciones.entries) {
      testWidgets('${e.key}: rechazo de permisos → aviso contextual, modo de consulta, historial conservado y sin éxito falso', (tester) async {
        final repo = _CotizacionesFalsas(_cotizacion, falla: _rechazoDePermisos());
        await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), cotizaciones: repo);
        expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsOneWidget, reason: 'antes del rechazo hay acciones');

        await e.value(tester);

        expect(repo.llamadas, [metodos[e.key]], reason: 'se intentó una sola vez y nada más');
        expect(find.text(mensajeNegociacionRestringida(e.key)), findsOneWidget);
        expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
        for (final ok in exitos) {
          expect(find.text(ok), findsNothing, reason: 'no hay mensaje de éxito: $ok');
        }
        expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsOneWidget);
        expect(find.text('Cotización en modo de consulta.'), findsOneWidget);
        // Sin acciones nuevas...
        expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Solicitar ajuste'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Rechazar oferta'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Cancelar cotización'), findsNothing);
        // ...pero el detalle y el chat siguen a la vista (consulta).
        expect(find.text('Café Y'), findsWidgets);
        expect(find.text('Abrir chat'), findsOneWidget);
        expect(repo.cotizacion.estado, EstadoCotizacion.ofertaEnviada, reason: 'el documento no cambió');
      });
    }

    testWidgets('«Volver a intentar» devuelve las acciones', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _rechazoDePermisos());
      await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), cotizaciones: repo);
      await acciones['aceptar la oferta']!(tester);
      expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('cotizacion_volver_a_intentar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsOneWidget);
    });

    testWidgets('un fallo que no es de permisos (sin conexión) usa el aviso estándar y NO activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _sinConexion());
      await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), cotizaciones: repo);
      await acciones['aceptar la oferta']!(tester);

      expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsWidgets);
      expect(find.text('Oferta aceptada'), findsNothing);
    });

    testWidgets('un «sin permisos» local (no es un rechazo de Firestore) tampoco activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: const RepoException(RepoErrorKind.sinPermisos, 'No participas en esta cotización.'));
      await montar(tester, const QuoteDetailScreen(quoteId: 'q1'), cotizaciones: repo);
      await acciones['aceptar la oferta']!(tester);

      expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsNothing);
      expect(find.text('No participas en esta cotización.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  /// Pantalla base con un botón «Abrir» que empuja [destino]; sirve para probar que salir funciona
  /// y que el modo de consulta no sobrevive a cerrar la pantalla.
  Widget baseCon(Widget Function() destino) => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino())),
              child: const Text('Abrir'),
            ),
          ),
        ),
      );

  bool campoHabilitado(WidgetTester tester, int i) =>
      tester.widget<TextField>(find.descendant(of: find.byType(TextFormField).at(i), matching: find.byType(TextField))).enabled ?? true;

  group('Formulario de ofertas del vendedor', () {
    final botonEnviar = find.widgetWithText(ElevatedButton, 'Enviar oferta');

    Future<void> llenarYEnviar(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), '20000');
      await tester.enterText(find.byType(TextFormField).at(2), '5 días hábiles');
      await tester.enterText(find.byType(TextFormField).at(3), 'Pago contra entrega');
      await tester.enterText(find.byType(TextFormField).at(4), 'Gracias por tu interés');
      await tester.pump();
      await tester.tap(botonEnviar);
      await tester.pumpAndSettle();
    }

    testWidgets('permission-denied activa el modo de consulta: aviso, botón y campos deshabilitados, datos visibles, sin éxito', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: _rechazoDePermisos());
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      expect(botonEnviar, findsOneWidget);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull, reason: 'antes del rechazo el envío está disponible');

      await llenarYEnviar(tester);

      expect(repo.llamadas, ['enviarOferta']);
      // Modo de consulta con el aviso pedido.
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsOneWidget);
      expect(find.text('Modo de consulta'), findsOneWidget);
      expect(find.text('Esta operación no está disponible por una restricción temporal en una de las cuentas.'), findsOneWidget);
      // Botón de envío deshabilitado y todos los campos editables deshabilitados.
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNull);
      for (var i = 0; i < 5; i++) {
        expect(campoHabilitado(tester, i), isFalse, reason: 'campo $i');
      }
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cambiar')).onPressed, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).onPressed, isNull);
      // Los datos escritos siguen visibles.
      expect(find.text('20000'), findsOneWidget);
      expect(find.text('5 días hábiles'), findsOneWidget);
      expect(find.text('Pago contra entrega'), findsOneWidget);
      expect(find.text('Gracias por tu interés'), findsOneWidget);
      // Ni éxito ni mensaje de error técnico; la pantalla sigue abierta.
      expect(find.byType(OfferFormScreen), findsOneWidget);
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
      expect(find.textContaining('enviada'), findsNothing);
      // Tocar el botón deshabilitado no repite la operación.
      await tester.tap(botonEnviar, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.llamadas.length, 1);
    });

    testWidgets('un error de conexión NO activa el modo de consulta y permite reintentar', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: _sinConexion());
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      await llenarYEnviar(tester);

      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
      expect(find.textContaining('Sin conexión'), findsWidgets);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
      expect(campoHabilitado(tester, 0), isTrue);
      expect(find.text('20000'), findsOneWidget);
      await tester.tap(botonEnviar);
      await tester.pumpAndSettle();
      expect(repo.llamadas.length, 2, reason: 'se pudo reintentar');
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
    });

    testWidgets('un tiempo de espera agotado (deadline-exceeded) NO activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded')));
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      await llenarYEnviar(tester);
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
    });

    testWidgets('un error de validación local (campos vacíos) no envía nada ni activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: _rechazoDePermisos());
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      await tester.tap(botonEnviar);
      await tester.pumpAndSettle();
      expect(repo.llamadas, isEmpty, reason: 'la validación local frena el envío');
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
      expect(campoHabilitado(tester, 0), isTrue);
    });

    testWidgets('un error de validación devuelto por el repositorio no activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: const RepoException(RepoErrorKind.validacion, 'El precio no es válido.'));
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      await llenarYEnviar(tester);
      expect(repo.llamadas, ['enviarOferta']);
      expect(find.text('El precio no es válido.'), findsOneWidget);
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
    });

    testWidgets('un «sin permisos» local (no es un rechazo de Firestore) no activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: const RepoException(RepoErrorKind.sinPermisos, 'No participas en esta cotización.'));
      await montar(tester, const OfferFormScreen(cotizacion: _solicitud), cotizaciones: repo, usuario: _vendedor);
      await llenarYEnviar(tester);
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing);
      expect(find.text('No participas en esta cotización.'), findsOneWidget);
    });

    testWidgets('salir sigue funcionando en modo de consulta y el modo no sobrevive a cerrar la pantalla', (tester) async {
      final repo = _CotizacionesFalsas(_solicitud, falla: _rechazoDePermisos());
      await montar(tester, baseCon(() => const OfferFormScreen(cotizacion: _solicitud)), cotizaciones: repo, usuario: _vendedor);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await llenarYEnviar(tester);
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(OfferFormScreen), findsNothing);
      expect(find.text('Abrir'), findsOneWidget);

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('oferta_modo_consulta')), findsNothing, reason: 'pantalla nueva, sin modo de consulta');
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Formulario de solicitud de cotización del comprador', () {
    final botonEnviar = find.widgetWithText(ElevatedButton, 'Enviar solicitud de cotización');

    Future<void> llenarYEnviar(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).at(0), '50');
      await tester.enterText(find.byType(TextFormField).at(1), 'Bogotá');
      await tester.pump();
      await tester.tap(botonEnviar);
      await tester.pumpAndSettle();
    }

    testWidgets('permission-denied activa el modo de consulta: formulario bloqueado, datos visibles, sin éxito', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _rechazoDePermisos());
      await montar(tester, const QuoteRequestScreen(conexion: _conexion), cotizaciones: repo, lotes: _LotesFalsos(lote: _lote));
      expect(botonEnviar, findsOneWidget);

      await llenarYEnviar(tester);

      expect(repo.llamadas, ['crearSolicitud']);
      expect(find.byKey(const ValueKey('cotizar_modo_consulta')), findsOneWidget);
      expect(find.text(mensajeFormularioSoloConsulta), findsOneWidget);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNull);
      for (var i = 0; i < 3; i++) {
        expect(campoHabilitado(tester, i), isFalse, reason: 'campo $i');
      }
      expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged, isNull);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Bogotá'), findsOneWidget);
      expect(find.byType(QuoteRequestScreen), findsOneWidget);
      expect(find.text('No tienes permiso para realizar esta acción.'), findsNothing);
    });

    testWidgets('un error de conexión NO activa el modo de consulta y permite reintentar', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _sinConexion());
      await montar(tester, const QuoteRequestScreen(conexion: _conexion), cotizaciones: repo, lotes: _LotesFalsos(lote: _lote));
      await llenarYEnviar(tester);
      expect(find.byKey(const ValueKey('cotizar_modo_consulta')), findsNothing);
      expect(find.textContaining('Sin conexión'), findsWidgets);
      expect(tester.widget<ElevatedButton>(botonEnviar).onPressed, isNotNull);
      expect(campoHabilitado(tester, 0), isTrue);
    });

    testWidgets('un error de validación local (cantidad vacía) no envía ni activa el modo de consulta', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _rechazoDePermisos());
      await montar(tester, const QuoteRequestScreen(conexion: _conexion), cotizaciones: repo, lotes: _LotesFalsos(lote: _lote));
      await tester.tap(botonEnviar);
      await tester.pumpAndSettle();
      expect(repo.llamadas, isEmpty);
      expect(find.byKey(const ValueKey('cotizar_modo_consulta')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('Consistencia del chat y de la cotización en modo de consulta', () {
    testWidgets('chat: tras el rechazo «Cotizar» queda deshabilitado, «Ver café» y salir siguen disponibles, y el modo no sobrevive al cerrar', (tester) async {
      final chats = _ChatsFalso(_mensajes, falla: _rechazoDePermisos());
      await montar(tester, baseCon(() => const ChatScreen(interestRequestId: 'comp_lote1', otroNombre: 'Finca X')), chats: chats);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cotizar')).onPressed, isNotNull);

      await tester.enterText(find.byType(TextField), 'Hola');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cotizar')).onPressed, isNull);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Ver café')).onPressed, isNotNull);
      expect(find.text('Hola, ¿sigue disponible el lote?'), findsOneWidget);
      expect(chats.intentos, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat_modo_consulta')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cotizar')).onPressed, isNotNull);
    });

    testWidgets('cotización: en modo de consulta no queda ninguna acción comercial, se puede volver atrás y el modo no sobrevive al cerrar', (tester) async {
      final repo = _CotizacionesFalsas(_cotizacion, falla: _rechazoDePermisos());
      await montar(tester, baseCon(() => const QuoteDetailScreen(quoteId: 'q1')), cotizaciones: repo);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Aceptar oferta'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(ElevatedButton, 'Aceptar oferta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsNothing, reason: 'sin botón principal');
      expect(find.widgetWithText(OutlinedButton, 'Solicitar ajuste'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Rechazar oferta'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Cancelar cotización'), findsNothing);
      expect(find.text('Abrir chat'), findsOneWidget);
      expect(repo.llamadas.length, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(QuoteDetailScreen), findsNothing);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cotizacion_modo_consulta')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Aceptar oferta'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  group('StreamView: un evento null es un dato, no «cargando»', () {
    testWidgets('un stream nullable que emite null (documento inexistente) llega al builder y no deja el indicador girando', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StreamView<String?>(crear: () => Stream<String?>.value(null), builder: (c, d) => Text(d == null ? 'sin documento' : d))),
      ));
      await tester.pumpAndSettle(); // si siguiera el indicador, esto agotaría el tiempo
      expect(find.text('sin documento'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('mientras no llega ningún evento se muestra el indicador, y al llegar el dato se muestra el dato', (tester) async {
      final ctrl = StreamController<String>();
      addTearDown(ctrl.close);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StreamView<String>(crear: () => ctrl.stream, builder: (c, d) => Text(d)))));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      ctrl.add('listo');
      await tester.pump();
      expect(find.text('listo'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
