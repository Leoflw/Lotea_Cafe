import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/interest_request.dart';
import 'package:lotea_cafe/repositories/chat_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';

const _comprador = 'buyer1';
const _vendedor = 'seller1';
const _ajeno = 'otro';
const _id = 'buyer1_lot1';

InterestRequest _conexion({
  EstadoSolicitud estado = EstadoSolicitud.aceptada,
  DateTime? mensajeAt,
  String? mensajeDe,
  DateTime? leidoComprador,
  DateTime? leidoVendedor,
}) =>
    InterestRequest(
      id: _id,
      compradorId: _comprador,
      sellerId: _vendedor,
      coffeeLotId: 'lot1',
      estado: estado,
      ultimoMensajeAt: mensajeAt,
      ultimoMensajeDe: mensajeDe,
      leidoComprador: leidoComprador,
      leidoVendedor: leidoVendedor,
    );

final _t1 = DateTime(2026, 10, 23, 10, 0);
final _t2 = DateTime(2026, 10, 23, 10, 5);
final _t3 = DateTime(2026, 10, 23, 10, 10);

Future<void> _pausa() => Future<void>.delayed(const Duration(milliseconds: 15));

void main() {
  group('InterestRequest.tieneMensajesNoLeidos', () {
    test('un mensaje que envió el propio usuario NUNCA cuenta como recibido', () {
      final c = _conexion(mensajeAt: _t1, mensajeDe: _comprador);
      expect(c.tieneMensajesNoLeidos(_comprador), isFalse);
    });

    test('un mensaje recibido sin leer activa el indicador del destinatario', () {
      final c = _conexion(mensajeAt: _t1, mensajeDe: _comprador);
      expect(c.tieneMensajesNoLeidos(_vendedor), isTrue);
      final inversa = _conexion(mensajeAt: _t1, mensajeDe: _vendedor);
      expect(inversa.tieneMensajesNoLeidos(_comprador), isTrue);
      expect(inversa.tieneMensajesNoLeidos(_vendedor), isFalse);
    });

    test('al leer (marca posterior al mensaje) el indicador desaparece', () {
      final c = _conexion(mensajeAt: _t1, mensajeDe: _comprador, leidoVendedor: _t2);
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
    });

    test('un mensaje nuevo posterior a la última lectura vuelve a activarlo', () {
      final c = _conexion(mensajeAt: _t3, mensajeDe: _comprador, leidoVendedor: _t2);
      expect(c.tieneMensajesNoLeidos(_vendedor), isTrue);
    });

    test('el estado de lectura es independiente por participante', () {
      // El vendedor ya leyó; el comprador envió el mensaje y no lo recibe.
      final c = _conexion(mensajeAt: _t1, mensajeDe: _comprador, leidoVendedor: _t2);
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
      // Que el comprador haya «leído» no afecta al vendedor.
      final c2 = _conexion(mensajeAt: _t1, mensajeDe: _comprador, leidoComprador: _t2);
      expect(c2.tieneMensajesNoLeidos(_vendedor), isTrue);
      expect(c2.leidoPor(_vendedor), isNull);
      expect(c2.leidoPor(_comprador), _t2);
    });

    test('una persona ajena a la conexión no tiene mensajes sin leer', () {
      final c = _conexion(mensajeAt: _t1, mensajeDe: _comprador);
      expect(c.tieneMensajesNoLeidos(_ajeno), isFalse);
      expect(c.tieneMensajesNoLeidos(''), isFalse);
      expect(c.leidoPor(_ajeno), isNull);
    });

    test('sin mensajes (o conexión anterior a esta función) no hay indicador', () {
      expect(_conexion().tieneMensajesNoLeidos(_vendedor), isFalse);
    });

    test('solo las conexiones aceptadas tienen chat', () {
      final c = _conexion(estado: EstadoSolicitud.pendiente, mensajeAt: _t1, mensajeDe: _comprador);
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
    });

    test('lee los campos de Firestore y una marca pendiente del servidor no «parpadea»', () {
      final base = {
        'compradorId': _comprador,
        'sellerId': _vendedor,
        'coffeeLotId': 'lot1',
        'estado': 'aceptada',
        'ultimoMensajeAt': Timestamp.fromDate(_t1),
        'ultimoMensajeDe': _comprador,
      };
      expect(InterestRequest.fromMap(_id, base).tieneMensajesNoLeidos(_vendedor), isTrue);
      expect(InterestRequest.fromMap(_id, {...base, 'leidoVendedor': Timestamp.fromDate(_t2)}).tieneMensajesNoLeidos(_vendedor), isFalse);
      // Escritura local aún sin confirmar: el campo existe pero sin valor.
      expect(InterestRequest.fromMap(_id, {...base, 'leidoVendedor': null}).tieneMensajesNoLeidos(_vendedor), isFalse);
    });
  });

  group('persistencia y lectura en Firestore (fake)', () {
    late FakeFirebaseFirestore db;
    late ChatRepository chats;
    late InterestRequestRepository solicitudes;

    Future<InterestRequest> leer() async => (await solicitudes.obtener(_id))!;

    setUp(() async {
      db = FakeFirebaseFirestore();
      chats = ChatRepository(db: db);
      solicitudes = InterestRequestRepository(db: db);
      await db.collection('interestRequests').doc(_id).set({
        'compradorId': _comprador,
        'sellerId': _vendedor,
        'coffeeLotId': 'lot1',
        'estado': 'aceptada',
        'compradorNombre': 'juan',
        'sellerNombre': 'dyd',
        'loteNombre': 'ffff',
      });
    });

    test('enviar guarda el mensaje y el «último mensaje» de la conexión', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      final mensajes = await db.collection('chats').doc(_id).collection('messages').get();
      expect(mensajes.docs.single.data()['texto'], 'Hola');
      final c = await leer();
      expect(c.ultimoMensajeDe, _comprador);
      expect(c.ultimoMensajeAt, isNotNull);
    });

    test('quien envía no ve indicador; quien recibe, sí', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      final c = await leer();
      expect(c.tieneMensajesNoLeidos(_comprador), isFalse);
      expect(c.tieneMensajesNoLeidos(_vendedor), isTrue);
    });

    test('al abrir el chat se marca leído solo para quien lo abre', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      await solicitudes.marcarChatLeido(_id, esComprador: false); // el vendedor abre el chat
      final c = await leer();
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
      expect(c.leidoVendedor, isNotNull);
      expect(c.leidoComprador, isNull, reason: 'el estado del comprador no se toca');
    });

    test('un mensaje nuevo después de leer vuelve a activar el indicador', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      await solicitudes.marcarChatLeido(_id, esComprador: false);
      await _pausa();
      await chats.enviar(chatId: _id, mensajeId: 'm2', senderId: _comprador, texto: '¿Sigues ahí?');
      expect((await leer()).tieneMensajesNoLeidos(_vendedor), isTrue);
    });

    test('la respuesta del vendedor activa el indicador del comprador y no el suyo', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      await solicitudes.marcarChatLeido(_id, esComprador: false);
      await _pausa();
      await chats.enviar(chatId: _id, mensajeId: 'm2', senderId: _vendedor, texto: 'Buenas');
      final c = await leer();
      expect(c.tieneMensajesNoLeidos(_comprador), isTrue);
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
    });

    test('el estado de lectura persiste: una instancia nueva de los repositorios lo ve igual', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await _pausa();
      await solicitudes.marcarChatLeido(_id, esComprador: false);
      final otraSesion = InterestRequestRepository(db: db);
      final c = (await otraSesion.obtener(_id))!;
      expect(c.tieneMensajesNoLeidos(_vendedor), isFalse);
      expect(c.leidoVendedor, isNotNull);
    });

    test('el indicador se actualiza en tiempo real desde el stream de la conexión', () async {
      final estados = <bool>[];
      final sub = solicitudes.observar(_id).listen((c) => estados.add(c?.tieneMensajesNoLeidos(_vendedor) ?? false));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(estados.last, isFalse);
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      await pumpEventQueue();
      expect(estados.last, isTrue);
      await _pausa();
      await solicitudes.marcarChatLeido(_id, esComprador: false);
      await pumpEventQueue();
      expect(estados.last, isFalse);
    });

    test('el último mensaje queda vinculado al id del mensaje creado en el mismo lote', () async {
      await chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: 'Hola');
      final c = await leer();
      expect(c.ultimoMensajeId, 'm1');
      final mensaje = await db.collection('chats').doc(_id).collection('messages').doc(c.ultimoMensajeId).get();
      expect(mensaje.exists, isTrue);
    });

    test('un mensaje vacío no se envía ni toca la conexión', () async {
      await expectLater(chats.enviar(chatId: _id, mensajeId: 'm1', senderId: _comprador, texto: '   '), throwsA(anything));
      expect((await leer()).ultimoMensajeDe, isNull);
    });
  });
}
