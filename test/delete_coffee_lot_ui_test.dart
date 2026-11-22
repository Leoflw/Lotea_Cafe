import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/lot_deletion.dart';
import 'package:lotea_cafe/models/seller_profile.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/favorite_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';
import 'package:lotea_cafe/repositories/lot_deletion_impact.dart';
import 'package:lotea_cafe/repositories/quote_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/screens/seller/coffee_lot_edit_screen.dart';
import 'package:lotea_cafe/screens/seller/my_coffee_lots_screen.dart';
import 'package:lotea_cafe/state/activity_provider.dart';
import 'package:lotea_cafe/state/remote.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/state/session_provider.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------------------------
// Dobles de prueba. Ninguno toca Firebase real ni ImageKit; la eliminación del repositorio se
// sustituye por un espía (su comportamiento real ya lo cubre image_cleanup_test.dart).
// ---------------------------------------------------------------------------------------------

class _SesionActivaFalsa extends ChangeNotifier
    implements SessionProvider {
  @override
  bool get operacionesBloqueadas => false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// Espía de `CoffeeLotRepository.eliminar`: registra las llamadas y puede quedarse esperando o fallar.
class _LotesEspia extends CoffeeLotRepository {
  _LotesEspia(FirebaseFirestore db) : super(db: db);
  final List<String> llamadas = [];
  Completer<void>? espera;
  Object? error;

  @override
  Future<void> eliminar(String lotId) async {
    llamadas.add(lotId);
    final e = error;
    if (e != null) throw e;
    final c = espera;
    if (c != null) await c.future;
  }
}

class _SolicitudesFalsas extends InterestRequestRepository {
  _SolicitudesFalsas(FirebaseFirestore db, {this.total = 0, this.falla}) : super(db: db);
  int total;
  Object? falla;
  final List<String> consultas = [];

  @override
  Future<int> contarDeLote({required String sellerId, required String coffeeLotId}) async {
    consultas.add('$sellerId/$coffeeLotId');
    final f = falla;
    if (f != null) throw f;
    return total;
  }
}

class _CotizacionesFalsas extends QuoteRepository {
  _CotizacionesFalsas(FirebaseFirestore db, {this.total = 0, this.falla}) : super(db: db);
  int total;
  Object? falla;
  final List<String> consultas = [];

  @override
  Future<int> contarDeLote({required String sellerId, required String coffeeLotId}) async {
    consultas.add('$sellerId/$coffeeLotId');
    final f = falla;
    if (f != null) throw f;
    return total;
  }
}

/// ActivityProvider con los datos del vendedor ya cargados (sin sesión ni streams).
class _ActividadFalsa extends ActivityProvider {
  _ActividadFalsa(FirebaseFirestore db, {required this.perfil, required this.lotes, this.estados = const {}})
      : super(
          sellers: SellerRepository(db: db),
          lots: CoffeeLotRepository(db: db),
          requests: InterestRequestRepository(db: db),
          favorites: FavoriteRepository(db: db),
          quotes: QuoteRepository(db: db),
        );

  final SellerProfile perfil;
  List<CoffeeLot> lotes;
  Map<String, EstadoEliminacionLote> estados;

  @override
  Remote<SellerProfile?> get perfilVendedor => Remote.listo(perfil);
  @override
  Remote<List<CoffeeLot>> get lotesPropios => Remote.listo(lotes);
  @override
  List<CoffeeLot> get listaLotesPropios => lotes;
  @override
  Remote<Map<String, EstadoEliminacionLote>> get eliminaciones => Remote.listo(estados);
  @override
  Map<String, EstadoEliminacionLote> get eliminacionesPropias => estados;
  @override
  EstadoEliminacionLote? eliminacionDe(String lotId) => estados[lotId];

  void cambiar({List<CoffeeLot>? lotes, Map<String, EstadoEliminacionLote>? estados}) {
    if (lotes != null) this.lotes = lotes;
    if (estados != null) this.estados = estados;
    notifyListeners();
  }
}

CoffeeLot _lote(String id, String nombre, {EstadoLote estado = EstadoLote.publicado}) => CoffeeLot(
      id: id,
      sellerId: 'u1',
      nombre: nombre,
      variedades: const ['Caturra'],
      proceso: 'Lavado',
      precioCOP: 32000,
      fotos: const [],
      fotosStoragePaths: const [],
      sellerNombreMarca: 'Finca La Esperanza',
      departamento: 'Huila',
      region: 'Huila',
      estado: estado,
    );

const _perfil = SellerProfile(
  id: 'u1',
  usuarioId: 'u1',
  nombreMarca: 'Finca La Esperanza',
  fincaPrincipal: 'La Esperanza',
  region: 'Huila',
  departamento: 'Huila',
);

void main() {
  late FakeFirebaseFirestore db;
  late _LotesEspia lotesRepo;
  late _SolicitudesFalsas solicitudes;
  late _CotizacionesFalsas cotizaciones;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    db = FakeFirebaseFirestore();
    lotesRepo = _LotesEspia(db);
    solicitudes = _SolicitudesFalsas(db, total: 3);
    cotizaciones = _CotizacionesFalsas(db, total: 1);
  });

  void pantalla(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);
  }

  Future<void> montar(WidgetTester tester, _ActividadFalsa actividad) async {
    pantalla(tester);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(
        value: _SesionActivaFalsa()
       ),
       ChangeNotifierProvider<ActivityProvider>.value(value: actividad),
       Provider<CoffeeLotRepository>.value(value: lotesRepo),
       Provider<InterestRequestRepository>.value(value: solicitudes),
       Provider<QuoteRepository>.value(value: cotizaciones),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const MyCoffeeLotsScreen()),
    ));
    await tester.pump();
  }

  _ActividadFalsa actividad({List<CoffeeLot>? lotes, Map<String, EstadoEliminacionLote> estados = const {}}) =>
      _ActividadFalsa(db, perfil: _perfil, lotes: lotes ?? [_lote('lot1', 'Caturra Lavado')], estados: estados);

  final botonEliminarFila = find.byTooltip('Eliminar café');
  // Por clave: mientras se elimina, el botón muestra el indicador y ya no tiene texto.
  final botonConfirmar = find.byKey(const ValueKey('confirmar_eliminar'));
  final botonCancelar = find.widgetWithText(TextButton, 'Cancelar');
  // `TextButton.icon` crea una subclase privada: `find.byType(TextButton)` no la encuentra.
  Finder textButtonCon(String texto) =>
      find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is TextButton));

  group('acción eliminar en «Mi catálogo»', () {
    testWidgets('se muestra en cafés publicados y en borradores, junto a editar/completar', (tester) async {
      final a = actividad(lotes: [
        _lote('lot1', 'Caturra Lavado'),
        _lote('lot2', 'Geisha Natural', estado: EstadoLote.borrador),
      ]);
      await montar(tester, a);
      expect(botonEliminarFila, findsNWidgets(2));
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Completar'), findsOneWidget);
    });

    testWidgets('la confirmación incluye el nombre del café y la explicación del historial', (tester) async {
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      final dialogo = find.byType(AlertDialog);
      expect(dialogo, findsOneWidget);
      expect(find.descendant(of: dialogo, matching: find.textContaining('«Caturra Lavado»')), findsOneWidget);
      expect(find.descendant(of: dialogo, matching: find.textContaining('negociaciones comerciales se conservan')), findsOneWidget);
      expect(find.descendant(of: dialogo, matching: find.textContaining('fotografías históricas')), findsOneWidget);
      expect(botonCancelar, findsOneWidget);
      expect(botonConfirmar, findsOneWidget);
    });

    testWidgets('muestra los contadores EXACTOS de ese café (no las listas limitadas a 100)', (tester) async {
      solicitudes.total = 250;
      cotizaciones.total = 1;
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('conteo_solicitudes'))).data, '• 250 solicitudes de interés');
      expect(tester.widget<Text>(find.byKey(const ValueKey('conteo_cotizaciones'))).data, '• 1 cotización');
      // Se cuentan por vendedor y café.
      expect(solicitudes.consultas, ['u1/lot1']);
      expect(cotizaciones.consultas, ['u1/lot1']);
    });

    testWidgets('singular y plural de los contadores', (tester) async {
      solicitudes.total = 1;
      cotizaciones.total = 0;
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('conteo_solicitudes'))).data, '• 1 solicitud de interés');
      // Cero REAL (la consulta salió bien): sí se muestra.
      expect(tester.widget<Text>(find.byKey(const ValueKey('conteo_cotizaciones'))).data, '• 0 cotizaciones');
    });

    testWidgets('cancelar no ejecuta ninguna modificación', (tester) async {
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      await tester.tap(botonCancelar);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(lotesRepo.llamadas, isEmpty);
      expect(find.text('Caturra Lavado'), findsOneWidget); // el café sigue como estaba
    });

    testWidgets('confirmar invoca CoffeeLotRepository.eliminar UNA sola vez con el id del café', (tester) async {
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      await tester.tap(botonConfirmar);
      await tester.pumpAndSettle();
      expect(lotesRepo.llamadas, ['lot1']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('ya no aparece en tu catálogo'), findsOneWidget);
    });

    testWidgets('dos toques seguidos en confirmar no ejecutan dos eliminaciones', (tester) async {
      lotesRepo.espera = Completer<void>();
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      // Sin `pump` entre toques: el segundo llega con el botón aún «habilitado» en el árbol.
      await tester.tap(botonConfirmar);
      await tester.tap(botonConfirmar);
      await tester.pump();
      expect(lotesRepo.llamadas, ['lot1']);
      // Indicador de proceso y nada más que se pueda pulsar.
      expect(find.byKey(const ValueKey('eliminando_progreso')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(botonConfirmar).onPressed, isNull);
      expect(tester.widget<TextButton>(botonCancelar).onPressed, isNull);
      lotesRepo.espera!.complete();
      await tester.pumpAndSettle();
      expect(lotesRepo.llamadas, ['lot1']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('mientras se elimina un café no se puede iniciar otra eliminación', (tester) async {
      lotesRepo.espera = Completer<void>();
      final a = actividad(lotes: [_lote('lot1', 'Caturra Lavado'), _lote('lot2', 'Geisha Natural')]);
      await montar(tester, a);
      await tester.tap(botonEliminarFila.first);
      await tester.pumpAndSettle();
      await tester.tap(botonConfirmar);
      await tester.pump();
      for (final b in tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_outline))) {
        expect(b.onPressed, isNull);
      }
      lotesRepo.espera!.complete();
      await tester.pumpAndSettle();
      // Terminada la primera, las acciones vuelven a estar disponibles.
      for (final b in tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_outline))) {
        expect(b.onPressed, isNotNull);
      }
      expect(lotesRepo.llamadas, ['lot1']);
    });

    testWidgets('si eliminar falla, el diálogo explica el error y permite reintentar', (tester) async {
      lotesRepo.error = const RepoException(RepoErrorKind.sinConexion, 'Sin conexión con el servidor.');
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      await tester.tap(botonConfirmar);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('error_eliminar')), findsOneWidget);
      expect(find.text('Sin conexión con el servidor.'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(botonConfirmar).onPressed, isNotNull);
      lotesRepo.error = null;
      await tester.tap(botonConfirmar);
      await tester.pumpAndSettle();
      expect(lotesRepo.llamadas, ['lot1', 'lot1']);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('errores al calcular los contadores', () {
    testWidgets('un fallo NO se presenta como cero: se avisa y no se puede confirmar', (tester) async {
      solicitudes.falla = const RepoException(RepoErrorKind.sinConexion, 'Sin conexión con el servidor.');
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conteos_error')), findsOneWidget);
      expect(find.textContaining('No pudimos calcular'), findsOneWidget);
      expect(find.byKey(const ValueKey('conteo_solicitudes')), findsNothing);
      expect(find.byKey(const ValueKey('conteo_cotizaciones')), findsNothing);
      expect(find.textContaining('0 solicitudes'), findsNothing);
      expect(find.textContaining('0 cotizaciones'), findsNothing);
      expect(tester.widget<ElevatedButton>(botonConfirmar).onPressed, isNull);
      // Pulsar confirmar (deshabilitado) no ejecuta nada.
      await tester.tap(botonConfirmar);
      await tester.pump();
      expect(lotesRepo.llamadas, isEmpty);
    });

    testWidgets('«Reintentar» vuelve a consultar y, si sale bien, muestra los números reales', (tester) async {
      cotizaciones.falla = const RepoException(RepoErrorKind.sinPermisos, 'No tienes permiso para realizar esta acción.');
      await montar(tester, actividad());
      await tester.tap(botonEliminarFila);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conteos_error')), findsOneWidget);
      cotizaciones.falla = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conteos_error')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('conteo_solicitudes'))).data, '• 3 solicitudes de interés');
      expect(tester.widget<ElevatedButton>(botonConfirmar).onPressed, isNotNull);
    });

    test('LotDeletionImpactCounter: si falla UNO de los dos conteos, falla (no devuelve 0)', () async {
      final contador = LotDeletionImpactCounter(
        solicitudes: _SolicitudesFalsas(db, total: 5),
        cotizaciones: _CotizacionesFalsas(db, falla: const RepoException(RepoErrorKind.sinConexion, 'sin red')),
      );
      await expectLater(contador.contar(sellerId: 'u1', coffeeLotId: 'lot1'), throwsA(isA<RepoException>()));
    });

    test('LotDeletionImpactCounter reúne ambos conteos', () async {
      final contador = LotDeletionImpactCounter(
        solicitudes: _SolicitudesFalsas(db, total: 7),
        cotizaciones: _CotizacionesFalsas(db, total: 2),
      );
      final r = await contador.contar(sellerId: 'u1', coffeeLotId: 'lot1');
      expect(r.solicitudes, 7);
      expect(r.cotizaciones, 2);
    });
  });

  group('estado pendiente de la eliminación', () {
    testWidgets('un café «pendiente» no se muestra como borrador editable ni se puede abrir', (tester) async {
      final a = actividad(
        lotes: [_lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador)],
        estados: {'lot1': EstadoEliminacionLote.pendiente},
      );
      await montar(tester, a);
      expect(find.byKey(const ValueKey('cafe_en_eliminacion_lot1')), findsOneWidget);
      expect(find.text('Eliminación pendiente'), findsOneWidget);
      expect(find.text('Borrador'), findsNothing);
      expect(find.text('Completar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(botonEliminarFila, findsNothing);
      expect(find.text('Reintentar eliminación'), findsNothing);
      await tester.tap(find.text('Caturra Lavado'));
      await tester.pumpAndSettle();
      expect(find.byType(CoffeeLotEditScreen), findsNothing);
      // No cuenta como borrador en los filtros.
      expect(find.text('Todos · 1'), findsOneWidget);

      final listaFiltros = find.byType(ListView).at(1);
      final scrollableFiltros = find.descendant(
        of: listaFiltros,
        matching: find.byType(Scrollable),
      ).first;

      await tester.scrollUntilVisible(
        find.text('Borradores · 0'),
        100,
        scrollable: scrollableFiltros,
      );

      expect(find.text('Borradores · 0'), findsOneWidget);
    });

    testWidgets('«procesando» y «errorTemporal» se distinguen y tampoco ofrecen acciones', (tester) async {
      final a = actividad(
        lotes: [
          _lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador),
          _lote('lot2', 'Geisha Natural', estado: EstadoLote.borrador),
        ],
        estados: {'lot1': EstadoEliminacionLote.procesando, 'lot2': EstadoEliminacionLote.errorTemporal},
      );
      await montar(tester, a);
      expect(find.text('Eliminando…'), findsOneWidget);
      expect(find.text('Eliminación en reintento'), findsOneWidget);
      expect(find.textContaining('se reintentará automáticamente'), findsOneWidget);
      expect(botonEliminarFila, findsNothing);
      expect(find.text('Reintentar eliminación'), findsNothing);
    });

    testWidgets('«fallido» informa del fallo y reenvía la eliminación con el método existente', (tester) async {
      final a = actividad(
        lotes: [_lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador)],
        estados: {'lot1': EstadoEliminacionLote.fallido},
      );
      await montar(tester, a);
      expect(find.text('No se pudo eliminar'), findsOneWidget);
      expect(find.text('Borrador'), findsNothing);
      expect(find.text('Completar'), findsNothing);
      await tester.tap(find.text('Reintentar eliminación'));
      await tester.pumpAndSettle();
      expect(lotesRepo.llamadas, ['lot1']);
    });

    testWidgets('el reintento no se puede duplicar mientras se envía', (tester) async {
      lotesRepo.espera = Completer<void>();
      final a = actividad(
        lotes: [_lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador)],
        estados: {'lot1': EstadoEliminacionLote.fallido},
      );
      await montar(tester, a);
      await tester.tap(find.text('Reintentar eliminación'));
      await tester.tap(find.text('Reintentar eliminación'));
      await tester.pump();
      expect(lotesRepo.llamadas, ['lot1']);
      expect(tester.widget<TextButton>(textButtonCon('Reintentar eliminación')).onPressed, isNull);
      lotesRepo.espera!.complete();
      await tester.pumpAndSettle();
      expect(lotesRepo.llamadas, ['lot1']);
    });

    testWidgets('«completado» oculta el café: no reaparece un instante como borrador', (tester) async {
      final a = actividad(
        lotes: [_lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador)],
        estados: {'lot1': EstadoEliminacionLote.completado},
      );
      await montar(tester, a);
      expect(find.text('Caturra Lavado'), findsNothing);
      expect(find.text('Borrador'), findsNothing);
    });

    testWidgets('al pasar de normal a pendiente la fila cambia de representación', (tester) async {
      final a = actividad(lotes: [_lote('lot1', 'Caturra Lavado')]);
      await montar(tester, a);
      expect(botonEliminarFila, findsOneWidget);
      a.cambiar(
        lotes: [_lote('lot1', 'Caturra Lavado', estado: EstadoLote.borrador)],
        estados: {'lot1': EstadoEliminacionLote.pendiente},
      );
      await tester.pump();
      expect(botonEliminarFila, findsNothing);
      expect(find.text('Eliminación pendiente'), findsOneWidget);
    });
  });

  group('modelo EstadoEliminacionLote', () {
    test('interpreta los estados del Worker e ignora los desconocidos', () {
      expect(EstadoEliminacionLote.desde('pendiente'), EstadoEliminacionLote.pendiente);
      expect(EstadoEliminacionLote.desde('procesando'), EstadoEliminacionLote.procesando);
      expect(EstadoEliminacionLote.desde('errorTemporal'), EstadoEliminacionLote.errorTemporal);
      expect(EstadoEliminacionLote.desde('fallido'), EstadoEliminacionLote.fallido);
      expect(EstadoEliminacionLote.desde('completado'), EstadoEliminacionLote.completado);
      expect(EstadoEliminacionLote.desde('rechazado'), isNull);
      expect(EstadoEliminacionLote.desde(null), isNull);
    });

    test('enCurso / fallo / terminado', () {
      expect(EstadoEliminacionLote.pendiente.enCurso, isTrue);
      expect(EstadoEliminacionLote.procesando.enCurso, isTrue);
      expect(EstadoEliminacionLote.errorTemporal.enCurso, isTrue);
      expect(EstadoEliminacionLote.fallido.enCurso, isFalse);
      expect(EstadoEliminacionLote.fallido.fallo, isTrue);
      expect(EstadoEliminacionLote.completado.terminado, isTrue);
    });
  });

  group('repositorios (con Firestore simulado)', () {
    Future<void> sembrar(String coleccion, String id, String sellerId, String lotId) =>
        db.collection(coleccion).doc(id).set({'sellerId': sellerId, 'coffeeLotId': lotId});

    test('contarDeLote cuenta solo las negociaciones de ESE vendedor y ESE café, sin tope de 100', () async {
      for (var i = 0; i < 120; i++) {
        await sembrar('interestRequests', 'a$i', 'u1', 'lot1');
      }
      await sembrar('interestRequests', 'otroCafe', 'u1', 'lot2');
      await sembrar('interestRequests', 'otroVendedor', 'u2', 'lot1');
      await sembrar('quotes', 'q1', 'u1', 'lot1');
      await sembrar('quotes', 'q2', 'u1', 'lot1');
      await sembrar('quotes', 'q3', 'u1', 'lot2');
      await sembrar('quotes', 'q4', 'u2', 'lot1');
      expect(await InterestRequestRepository(db: db).contarDeLote(sellerId: 'u1', coffeeLotId: 'lot1'), 120);
      expect(await QuoteRepository(db: db).contarDeLote(sellerId: 'u1', coffeeLotId: 'lot1'), 2);
      expect(await QuoteRepository(db: db).contarDeLote(sellerId: 'u1', coffeeLotId: 'sinNada'), 0);
    });

    test('observarEliminaciones devuelve el estado por lote e ignora estados desconocidos', () async {
      final col = db.collection('users').doc('u1').collection('pendingLotDeletions');
      await col.doc('lotA').set({'lotId': 'lotA', 'estado': 'pendiente'});
      await col.doc('lotB').set({'lotId': 'lotB', 'estado': 'completado'});
      await col.doc('lotC').set({'lotId': 'lotC', 'estado': 'rechazado'});
      final mapa = await CoffeeLotRepository(db: db).observarEliminaciones('u1').first;
      expect(mapa, {'lotA': EstadoEliminacionLote.pendiente, 'lotB': EstadoEliminacionLote.completado});
    });

    test('observarEliminaciones no mezcla las solicitudes de otra persona', () async {
      await db.collection('users').doc('u2').collection('pendingLotDeletions').doc('lotX').set({'lotId': 'lotX', 'estado': 'pendiente'});
      final mapa = await CoffeeLotRepository(db: db).observarEliminaciones('u1').first;
      expect(mapa, isEmpty);
    });
  });
}
