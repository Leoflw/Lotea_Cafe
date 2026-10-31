import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/interest_request.dart';
import 'package:lotea_cafe/models/quote_request.dart';
import 'package:lotea_cafe/repositories/chat_repository.dart';
import 'package:lotea_cafe/repositories/quote_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/services/push_notifier.dart';

const _comprador = 'buyer1';
const _vendedor = 'seller1';
const _conexionId = 'buyer1_lot1';

class _NotificadorFalso implements NotificadorPush {
  final List<String> mensajes = []; // 'conexion|mensaje'
  final List<String> cotizaciones = []; // 'cotizacion|evento'
  Object? falla;
  Future<void> Function()? alLlamar;

  @override
  Future<void> mensajeEnviado({required String conexionId, required String mensajeId}) async {
    mensajes.add('$conexionId|$mensajeId');
    await alLlamar?.call();
    if (falla != null) throw falla!;
  }

  @override
  Future<void> eventoDeCotizacion({required String quoteId, required String eventoId}) async {
    cotizaciones.add('$quoteId|$eventoId');
    await alLlamar?.call();
    if (falla != null) throw falla!;
  }
}

Future<void> _pausa() => Future<void>.delayed(const Duration(milliseconds: 10));

Future<String> _unicoEvento(FakeFirebaseFirestore db, String quoteId, String tipo) async {
  final q = await db.collection('quotes').doc(quoteId).collection('events').where('tipo', isEqualTo: tipo).get();
  expect(q.docs, hasLength(1));
  return q.docs.single.id;
}

const _conexion = InterestRequest(
  id: _conexionId,
  compradorId: _comprador,
  sellerId: _vendedor,
  coffeeLotId: 'lot1',
  estado: EstadoSolicitud.aceptada,
  compradorNombre: 'Ana',
  sellerNombre: 'Finca',
);

const _lote = CoffeeLot(
  id: 'lot1',
  sellerId: _vendedor,
  nombre: 'Caturra',
  variedades: ['Caturra'],
  proceso: 'Lavado',
  precioCOP: 1000,
  sellerNombreMarca: 'Finca',
  estado: EstadoLote.publicado,
);

Future<void> _sembrarCotizacion(FakeFirebaseFirestore db, EstadoCotizacion estado, {Map<String, dynamic>? oferta}) {
  return db.collection('quotes').doc('q1').set({
    'interestRequestId': _conexionId,
    'compradorId': _comprador,
    'sellerId': _vendedor,
    'coffeeLotId': 'lot1',
    'cantidad': 10.0,
    'unidad': 'kg',
    'estado': estado.name,
    'oferta': oferta,
    'compradorNombre': 'Ana',
    'sellerNombre': 'Finca',
    'loteNombre': 'Caturra',
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  });
}

Map<String, dynamic> _oferta({DateTime? vigencia}) => {
      'precioUnitarioCOP': 1000,
      'unidadPrecio': 'kg',
      'subtotalCOP': 10000,
      'envioCOP': 0,
      'totalCOP': 10000,
      'tiempoEntrega': '3 días',
      'vigenciaHasta': vigencia == null ? null : Timestamp.fromDate(vigencia),
      'condiciones': '',
      'mensaje': null,
      'version': 1,
    };

void main() {
  group('ChatRepository avisa DESPUÉS de confirmar el mensaje', () {
    late FakeFirebaseFirestore db;
    late _NotificadorFalso n;
    late ChatRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      n = _NotificadorFalso();
      repo = ChatRepository(db: db, notificador: n);
      await db.collection('interestRequests').doc(_conexionId).set({
        'compradorId': _comprador,
        'sellerId': _vendedor,
        'coffeeLotId': 'lot1',
        'estado': 'aceptada',
      });
    });

    test('un envío correcto notifica una vez con la conexión y el mensaje que se guardaron', () async {
      await repo.enviar(chatId: _conexionId, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      expect(n.mensajes, ['$_conexionId|m1']);
      final msg = await db.collection('chats').doc(_conexionId).collection('messages').doc('m1').get();
      expect(msg.exists, isTrue);
      final conexion = await db.collection('interestRequests').doc(_conexionId).get();
      expect(conexion.data()!['ultimoMensajeId'], 'm1');
      expect(conexion.data()!['ultimoMensajeDe'], _comprador);
    });

    test('un mensaje inválido (vacío o demasiado largo) NO notifica', () async {
      await expectLater(repo.enviar(chatId: _conexionId, mensajeId: 'm1', senderId: _comprador, texto: '  '), throwsA(isA<RepoException>()));
      await expectLater(
        repo.enviar(chatId: _conexionId, mensajeId: 'm2', senderId: _comprador, texto: 'x' * (ChatRepository.maxCaracteres + 1)),
        throwsA(isA<RepoException>()),
      );
      await _pausa();
      expect(n.mensajes, isEmpty);
    });

    test('cuando se avisa, el mensaje y el «último mensaje» YA están guardados (nunca antes)', () async {
      bool? mensajeYaGuardado;
      String? ultimoYaGuardado;
      n.alLlamar = () async {
        mensajeYaGuardado = (await db.collection('chats').doc(_conexionId).collection('messages').doc('m1').get()).exists;
        ultimoYaGuardado = (await db.collection('interestRequests').doc(_conexionId).get()).data()!['ultimoMensajeId'] as String?;
      };
      await repo.enviar(chatId: _conexionId, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      expect(mensajeYaGuardado, isTrue);
      expect(ultimoYaGuardado, 'm1');
    });

    test('un fallo del aviso no hace fallar ni deshace el mensaje ya guardado', () async {
      n.falla = StateError('el Worker no responde');
      await repo.enviar(chatId: _conexionId, mensajeId: 'm1', senderId: _comprador, texto: 'Hola'); // no lanza
      await _pausa();
      expect(n.mensajes, hasLength(1));
      expect((await db.collection('chats').doc(_conexionId).collection('messages').doc('m1').get()).exists, isTrue);
    });

    test('un aviso lento no retrasa el envío (no se espera)', () async {
      n.alLlamar = () => Future<void>.delayed(const Duration(seconds: 5));
      final reloj = Stopwatch()..start();
      await repo.enviar(chatId: _conexionId, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      expect(reloj.elapsedMilliseconds, lessThan(2000));
    });

    test('sin notificador (como en las pruebas existentes) funciona igual', () async {
      final sola = ChatRepository(db: db);
      await sola.enviar(chatId: _conexionId, mensajeId: 'm9', senderId: _comprador, texto: 'Hola');
    });
  });

  group('QuoteRepository avisa con el id del evento creado, DESPUÉS de la transacción', () {
    late FakeFirebaseFirestore db;
    late _NotificadorFalso n;
    late QuoteRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      n = _NotificadorFalso();
      repo = QuoteRepository(db: db, notificador: n);
    });

    test('solicitud creada: notifica con el id del evento «solicitudCreada» guardado', () async {
      await repo.crearSolicitud(
        quoteId: 'q1',
        conexion: _conexion,
        lote: _lote,
        compradorUid: _comprador,
        cantidad: 10,
        unidad: 'kg',
      );
      await _pausa();
      final eventoId = await _unicoEvento(db, 'q1', EventoCotizacion.solicitudCreada.name);
      expect(n.cotizaciones, ['q1|$eventoId']);
    });

    test('cuando se avisa, el evento y el nuevo estado YA están guardados (nunca antes)', () async {
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      bool? eventoGuardado;
      String? estadoGuardado;
      n.alLlamar = () async {
        final q = await db.collection('quotes').doc('q1').get();
        estadoGuardado = q.data()!['estado'] as String?;
        eventoGuardado = (await db.collection('quotes').doc('q1').collection('events').get()).docs.isNotEmpty;
      };
      await repo.rechazarSolicitud(quoteId: 'q1', vendedorUid: _vendedor);
      await _pausa();
      expect(eventoGuardado, isTrue);
      expect(estadoGuardado, EstadoCotizacion.solicitudRechazada.name);
    });

    test('reintentar la MISMA solicitud (ya existe) no vuelve a notificar', () async {
      Future<void> crear() => repo.crearSolicitud(
            quoteId: 'q1',
            conexion: _conexion,
            lote: _lote,
            compradorUid: _comprador,
            cantidad: 10,
            unidad: 'kg',
          );
      await crear();
      await crear();
      await _pausa();
      expect(n.cotizaciones, hasLength(1));
      final eventos = await db.collection('quotes').doc('q1').collection('events').get();
      expect(eventos.docs, hasLength(1));
    });

    test('una solicitud inválida no notifica', () async {
      await expectLater(
        repo.crearSolicitud(quoteId: 'q1', conexion: _conexion, lote: _lote, compradorUid: _comprador, cantidad: 0, unidad: 'kg'),
        throwsA(isA<RepoException>()),
      );
      await _pausa();
      expect(n.cotizaciones, isEmpty);
    });

    test('rechazar solicitud (vendedor): notifica con el evento «solicitudRechazada»', () async {
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      await repo.rechazarSolicitud(quoteId: 'q1', vendedorUid: _vendedor, motivo: 'Sin stock');
      await _pausa();
      final id = await _unicoEvento(db, 'q1', EventoCotizacion.solicitudRechazada.name);
      expect(n.cotizaciones, ['q1|$id']);
    });

    test('enviar oferta (vendedor): notifica con el evento «ofertaEnviada»', () async {
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      await repo.enviarOferta(quoteId: 'q1', vendedorUid: _vendedor, precioUnitarioCOP: 1200, envioCOP: 0, tiempoEntrega: '3 días');
      await _pausa();
      final id = await _unicoEvento(db, 'q1', EventoCotizacion.ofertaEnviada.name);
      expect(n.cotizaciones, ['q1|$id']);
    });

    test('aceptar, rechazar oferta, pedir ajuste y cancelar (comprador): cada uno notifica su evento', () async {
      final futuro = DateTime.now().add(const Duration(days: 5));
      for (final caso in [
        (EventoCotizacion.ofertaAceptada, () => repo.aceptarOferta(quoteId: 'q1', compradorUid: _comprador)),
        (EventoCotizacion.ofertaRechazada, () => repo.rechazarOferta(quoteId: 'q1', compradorUid: _comprador, motivo: 'caro')),
        (EventoCotizacion.revisionSolicitada, () => repo.solicitarRevision(quoteId: 'q1', compradorUid: _comprador, comentario: 'baja el precio')),
        (EventoCotizacion.cancelada, () => repo.cancelar(quoteId: 'q1', compradorUid: _comprador)),
      ]) {
        db = FakeFirebaseFirestore();
        n = _NotificadorFalso();
        repo = QuoteRepository(db: db, notificador: n);
        await _sembrarCotizacion(db, EstadoCotizacion.ofertaEnviada, oferta: _oferta(vigencia: futuro));
        await caso.$2();
        await _pausa();
        final id = await _unicoEvento(db, 'q1', caso.$1.name);
        expect(n.cotizaciones, ['q1|$id'], reason: caso.$1.name);
      }
    });

    test('una transición NO permitida falla y no notifica (no hay evento que avisar)', () async {
      await _sembrarCotizacion(db, EstadoCotizacion.ofertaAceptada, oferta: _oferta());
      await expectLater(repo.cancelar(quoteId: 'q1', compradorUid: _comprador), throwsA(isA<RepoException>()));
      await expectLater(repo.rechazarSolicitud(quoteId: 'q1', vendedorUid: _vendedor), throwsA(isA<RepoException>()));
      await _pausa();
      expect(n.cotizaciones, isEmpty);
    });

    test('una persona ajena no puede transicionar ni dispara avisos', () async {
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      await expectLater(repo.rechazarSolicitud(quoteId: 'q1', vendedorUid: 'intruso'), throwsA(isA<RepoException>()));
      await _pausa();
      expect(n.cotizaciones, isEmpty);
    });

    test('la cotización inexistente no notifica', () async {
      await expectLater(repo.cancelar(quoteId: 'no-existe', compradorUid: _comprador), throwsA(isA<RepoException>()));
      await _pausa();
      expect(n.cotizaciones, isEmpty);
    });

    test('un fallo del aviso NO hace fallar ni deshace la operación comercial ya guardada', () async {
      n.falla = Exception('el Worker no responde');
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      await repo.rechazarSolicitud(quoteId: 'q1', vendedorUid: _vendedor); // no lanza
      await _pausa();
      expect(n.cotizaciones, hasLength(1));
      final q = await db.collection('quotes').doc('q1').get();
      expect(q.data()!['estado'], EstadoCotizacion.solicitudRechazada.name);
    });

    test('sin notificador funciona igual que antes', () async {
      final sola = QuoteRepository(db: db);
      await _sembrarCotizacion(db, EstadoCotizacion.solicitudPendiente);
      await sola.rechazarSolicitud(quoteId: 'q1', vendedorUid: _vendedor);
    });
  });
}
