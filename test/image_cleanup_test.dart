import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/seller_profile.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/image_cleanup_client.dart';
import 'package:lotea_cafe/repositories/pending_deletions.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/utils/photo_cleanup.dart';

// fileId de ImageKit de ejemplo (24 caracteres).
const _a = 'aaaaaaaaaaaaaaaaaaaaaa01';
const _b = 'bbbbbbbbbbbbbbbbbbbbbb02';
const _c = 'cccccccccccccccccccccc03';
const _urlA = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/a.jpg';
const _urlB = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/b.jpg';
const _urlC = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/c.jpg';

CoffeeLot _lote(List<String> fotos, List<String> ids, {EstadoLote estado = EstadoLote.publicado}) => CoffeeLot(
      id: '',
      sellerId: 'u1',
      nombre: 'Caturra Lavado',
      variedades: const ['Caturra'],
      proceso: 'Lavado',
      precioCOP: 32000,
      fotos: fotos,
      fotosStoragePaths: ids,
      sellerNombreMarca: 'Finca La Esperanza',
      departamento: 'Huila',
      region: 'Huila',
      estado: estado,
    );

SellerProfile _perfil({String? principal, String? idPrincipal, List<String> galeria = const [], List<String> ids = const [], String nombre = 'Finca La Esperanza'}) => SellerProfile(
      id: 'u1',
      usuarioId: 'u1',
      nombreMarca: nombre,
      fincaPrincipal: 'La Esperanza',
      fotoPrincipal: principal,
      fotoPrincipalStoragePath: idPrincipal,
      galeria: galeria,
      galeriaStoragePaths: ids,
      region: 'Huila',
      departamento: 'Huila',
    );

void main() {
  late FakeFirebaseFirestore db;
  late int avisos;
  late CoffeeLotRepository lotes;
  late SellerRepository vendedores;

  setUp(() {
    db = FakeFirebaseFirestore();
    avisos = 0;
    Future<void> aviso() async => avisos++;
    lotes = CoffeeLotRepository(db: db, alRetirarFotos: aviso);
    vendedores = SellerRepository(db: db, alRetirarFotos: aviso);
  });

  CollectionReference<Map<String, dynamic>> cola() => db.collection('users').doc('u1').collection('pendingFileDeletions');
  Future<List<String>> idsEncolados() async => (await cola().get()).docs.map((d) => d.id).toList()..sort();
  Future<void> esperarAvisos() => Future<void>.delayed(Duration.zero);
  CollectionReference<Map<String, dynamic>> colaDe(String uid) => db.collection('users').doc(uid).collection('pendingFileDeletions');
  Future<String?> estadoDe(String uid, String id) async => (await colaDe(uid).doc(id).get()).data()?['estado'] as String?;

  /// Solicitud de borrado de foto tal como la deja el Worker tras agotar los intentos (por defecto «fallido»).
  Future<void> sembrar(String uid, String id, {required String origen, required String refId, String estado = 'fallido'}) =>
      colaDe(uid).doc(id).set({
        'fileId': id,
        'origen': origen,
        'refId': refId,
        'estado': estado,
        'intentos': 6,
        'ultimoError': 'imagekit_credenciales',
        'createdAt': Timestamp.fromDate(DateTime(2020)),
      });

  group('PhotoCleanup.retirados', () {
    test('devuelve solo los ids que ya no están, sin repetidos', () {
      expect(PhotoCleanup.retirados(previos: [_a, _b, _b], actuales: [_a]), [_b]);
    });
    test('una foto que se conserva nunca se pide borrar', () {
      expect(PhotoCleanup.retirados(previos: [_a, _b], actuales: [_b, _a]), isEmpty);
    });
    test('ignora vacíos (fotos antiguas sin fileId) e ids con forma inválida', () {
      expect(PhotoCleanup.retirados(previos: ['', '  ', 'corto', 'con espacios 12345', _a], actuales: const []), [_a]);
    });
  });

  group('lotes', () {
    test('sustituir una foto: la nueva queda guardada y la vieja se encola EN LA MISMA operación', () async {
      final id = await lotes.guardarLote(_lote([_urlA, _urlB], [_a, _b]));
      expect(await idsEncolados(), isEmpty); // un lote nuevo no retira nada
      await lotes.guardarLote(_lote([_urlA, _urlC], [_a, _c]), idExistente: id);
      final lote = (await db.collection('coffeeLots').doc(id).get()).data()!;
      expect(lote['fotosStoragePaths'], [_a, _c]);
      expect(await idsEncolados(), [_b]);
      final solicitud = (await cola().doc(_b).get()).data()!;
      expect(solicitud['estado'], 'pendiente');
      expect(solicitud['origen'], 'lot');
      expect(solicitud['refId'], id);
      expect(solicitud['fileId'], _b);
      expect(solicitud.keys.toSet(), {'fileId', 'origen', 'refId', 'estado', 'createdAt'});
      await esperarAvisos();
      expect(avisos, 1);
    });

    test('quitar una foto la encola; quitar todas encola todas', () async {
      final id = await lotes.guardarLote(_lote([_urlA, _urlB], [_a, _b]));
      await lotes.guardarLote(_lote([_urlA], [_a]), idExistente: id);
      expect(await idsEncolados(), [_b]);
      await lotes.guardarLote(_lote(const [], const [], estado: EstadoLote.borrador), idExistente: id);
      expect(await idsEncolados(), [_a, _b]);
    });

    test('guardar sin cambiar fotos no encola nada ni avisa al Worker', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.guardarLote(_lote([_urlA], [_a]), idExistente: id);
      expect(await idsEncolados(), isEmpty);
      await esperarAvisos();
      expect(avisos, 0);
    });

    test('repetir la misma sustitución no duplica ni rompe la solicitud (idempotente)', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.guardarLote(_lote([_urlB], [_b]), idExistente: id);
      await cola().doc(_a).update({'estado': 'errorTemporal', 'intentos': 2}); // el Worker ya la tocó
      // Simula un reintento de la misma operación con el documento aún apuntando a _a.
      await db.collection('coffeeLots').doc(id).update({'fotos': [_urlA], 'fotosStoragePaths': [_a]});
      await lotes.guardarLote(_lote([_urlB], [_b]), idExistente: id);
      final solicitud = (await cola().doc(_a).get()).data()!;
      expect(solicitud['estado'], 'errorTemporal'); // no se pisó el estado del Worker
      expect(solicitud['intentos'], 2);
    });

    test('una solicitud que el Worker dejó «enUso» se vuelve a pedir', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await cola().doc(_a).set({'fileId': _a, 'origen': 'lot', 'estado': 'enUso', 'intentos': 0});
      await lotes.guardarLote(_lote([_urlB], [_b]), idExistente: id);
      expect((await cola().doc(_a).get()).data()!['estado'], 'pendiente');
    });

    test('las fotos antiguas sin fileId no producen solicitudes', () async {
      final id = await lotes.guardarLote(_lote([_urlA], ['']));
      await lotes.guardarLote(_lote([_urlB], [_b]), idExistente: id);
      expect(await idsEncolados(), isEmpty);
    });

    test('un fallo del aviso al Worker no afecta a lo guardado', () async {
      final repo = CoffeeLotRepository(db: db, alRetirarFotos: () async => throw StateError('sin red'));
      final id = await repo.guardarLote(_lote([_urlA], [_a]));
      await repo.guardarLote(_lote([_urlB], [_b]), idExistente: id);
      await esperarAvisos();
      expect(await idsEncolados(), [_a]);
    });

    test('eliminar un lote PIDE su eliminación: sin fotos, encola todas y crea la solicitud del lote', () async {
      final id = await lotes.guardarLote(_lote([_urlA, _urlB], [_a, _b]));
      await lotes.eliminar(id);
      // La app no borra el documento: lo completa el Worker (tras limpiar el historial).
      final lote = (await db.collection('coffeeLots').doc(id).get()).data()!;
      expect(lote['fotos'], isEmpty);
      expect(lote['fotosStoragePaths'], isEmpty);
      expect(lote['estado'], 'borrador'); // ya no aparece en el catálogo
      expect(await idsEncolados(), [_a, _b]);
      final solicitud = (await db.collection('users').doc('u1').collection('pendingLotDeletions').doc(id).get()).data()!;
      expect(solicitud['estado'], 'pendiente');
      expect(solicitud['lotId'], id);
      expect(solicitud.keys.toSet(), {'lotId', 'estado', 'createdAt'});
      await esperarAvisos();
      expect(avisos, 1);
    });

    test('pedir dos veces la eliminación del mismo lote no duplica ni pisa el estado del Worker', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.eliminar(id);
      final solicitudes = db.collection('users').doc('u1').collection('pendingLotDeletions');
      await solicitudes.doc(id).update({'estado': 'procesando', 'intentos': 1});
      await lotes.eliminar(id);
      final s = (await solicitudes.doc(id).get()).data()!;
      expect(s['estado'], 'procesando');
      expect(s['intentos'], 1);
      expect((await solicitudes.get()).docs.length, 1);
    });

    // ---- Reapertura de solicitudes «fallido» ----
    CollectionReference<Map<String, dynamic>> colaLotes(String uid) => db.collection('users').doc(uid).collection('pendingLotDeletions');
    CollectionReference<Map<String, dynamic>> colaFotos(String uid) => db.collection('users').doc(uid).collection('pendingFileDeletions');

    /// Un lote ya pedido para eliminar (queda sin fotos) cuyas solicitudes agotaron los intentos.
    Future<String> loteConSolicitudesFallidas() async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.eliminar(id);
      final falla = {'estado': 'fallido', 'intentos': 6, 'ultimoError': 'imagekit_5xx'};
      await colaLotes('u1').doc(id).update(falla);
      await colaFotos('u1').doc(_a).update(falla);
      return id;
    }

    test('repetir la eliminación reabre la solicitud de FOTO «fallido» aunque el lote ya no tenga fotos', () async {
      final id = await loteConSolicitudesFallidas();
      await lotes.eliminar(id);
      final foto = (await colaFotos('u1').doc(_a).get()).data()!;
      expect(foto['estado'], 'pendiente');
      expect(foto['createdAt'], isNotNull);
      // La app solo cambia estado y createdAt (lo único que permiten las reglas): el contador y el
      // último error son del Worker, que los reinicia al reclamar la solicitud reabierta.
      expect(foto['intentos'], 6);
      expect(foto['ultimoError'], 'imagekit_5xx');
    });

    test('repetir la eliminación reabre la solicitud de LOTE «fallido»', () async {
      final id = await loteConSolicitudesFallidas();
      await lotes.eliminar(id);
      final lote = (await colaLotes('u1').doc(id).get()).data()!;
      expect(lote['estado'], 'pendiente');
      expect(lote['lotId'], id);
      expect(lote['intentos'], 6); // lo reinicia el Worker, no la app
    });

    test('una solicitud COMPLETADA no se reabre ni se vuelve a pedir por accidente', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.eliminar(id);
      await colaLotes('u1').doc(id).update({'estado': 'completado'});
      await colaFotos('u1').doc(_a).update({'estado': 'completado'});
      await lotes.eliminar(id);
      await lotes.eliminar(id);
      expect((await colaLotes('u1').doc(id).get()).data()!['estado'], 'completado');
      expect((await colaFotos('u1').doc(_a).get()).data()!['estado'], 'completado');
    });

    test('«retenida», «enUso», «procesando» y «errorTemporal» no se reabren desde la app', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.eliminar(id);
      const otros = {'retenida': _b, 'enUso': _c, 'procesando': 'dddddddddddddddddddddd04', 'errorTemporal': 'eeeeeeeeeeeeeeeeeeeeee05'};
      for (final e in otros.entries) {
        await colaFotos('u1').doc(e.value).set({'fileId': e.value, 'origen': 'lot', 'refId': id, 'estado': e.key});
      }
      await lotes.eliminar(id);
      for (final e in otros.entries) {
        expect((await colaFotos('u1').doc(e.value).get()).data()!['estado'], e.key, reason: e.key);
      }
    });

    test('una solicitud «fallido» de OTRO lote no se reabre al eliminar este', () async {
      final id = await loteConSolicitudesFallidas();
      await colaFotos('u1').doc(_b).set({'fileId': _b, 'origen': 'lot', 'refId': 'otroLote', 'estado': 'fallido'});
      await lotes.eliminar(id);
      expect((await colaFotos('u1').doc(_b).get()).data()!['estado'], 'fallido');
      expect((await colaFotos('u1').doc(_a).get()).data()!['estado'], 'pendiente');
    });

    test('eliminar un lote NO reabre solicitudes de origen «profile» aunque su refId coincida con el id del lote', () async {
      final id = await loteConSolicitudesFallidas();
      await sembrar('u1', _c, origen: 'profile', refId: id);
      await lotes.eliminar(id);
      expect(await estadoDe('u1', _c), 'fallido');
      expect(await estadoDe('u1', _a), 'pendiente'); // la de origen lot sí
    });

    test('nunca toca solicitudes de OTRA persona, aunque tengan los mismos ids y estén «fallido»', () async {
      final id = await loteConSolicitudesFallidas();
      await colaFotos('u2').doc(_a).set({'fileId': _a, 'origen': 'lot', 'refId': id, 'estado': 'fallido'});
      await colaLotes('u2').doc(id).set({'lotId': id, 'estado': 'fallido'});
      await lotes.eliminar(id);
      expect((await colaFotos('u2').doc(_a).get()).data()!['estado'], 'fallido');
      expect((await colaLotes('u2').doc(id).get()).data()!['estado'], 'fallido');
      expect((await colaFotos('u1').doc(_a).get()).data()!['estado'], 'pendiente');
    });

    test('reintentar la reapertura no duplica solicitudes y es idempotente', () async {
      final id = await loteConSolicitudesFallidas();
      for (var i = 0; i < 3; i++) {
        await lotes.eliminar(id);
      }
      expect((await colaFotos('u1').get()).docs.length, 1);
      expect((await colaLotes('u1').get()).docs.length, 1);
      expect((await colaFotos('u1').doc(_a).get()).data()!['estado'], 'pendiente');
      expect((await colaLotes('u1').doc(id).get()).data()!['estado'], 'pendiente');
    });

    test('si la foto «fallido» sigue en el lote, se reabre UNA sola vez (sin doble escritura en el lote atómico)', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await colaFotos('u1').doc(_a).set({'fileId': _a, 'origen': 'lot', 'refId': id, 'estado': 'fallido'});
      await lotes.eliminar(id);
      expect((await colaFotos('u1').doc(_a).get()).data()!['estado'], 'pendiente');
      expect((await colaFotos('u1').get()).docs.length, 1);
    });

    test('una foto «retenida» por el historial no se reabre desde la app', () async {
      final id = await lotes.guardarLote(_lote([_urlA], [_a]));
      await lotes.guardarLote(_lote([_urlB], [_b]), idExistente: id); // encola _a
      await cola().doc(_a).update({'estado': 'retenida'});
      await lotes.guardarLote(_lote([_urlC], [_c]), idExistente: id); // encola _b; _a no se toca
      expect((await cola().doc(_a).get()).data()!['estado'], 'retenida');
    });
  });

  group('perfil del vendedor', () {
    test('sustituir la foto principal encola la anterior', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a));
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      expect(await idsEncolados(), [_a]);
      expect((await cola().doc(_a).get()).data()!['origen'], 'profile');
    });

    test('quitar la foto principal y fotos de galería las encola; las que se conservan no', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB, _urlC], ids: [_b, _c]));
      await vendedores.guardarPerfil(_perfil(galeria: [_urlC], ids: [_c]));
      expect(await idsEncolados(), [_a, _b]);
    });

    test('guardar el perfil sin cambiar fotos no encola nada', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB], ids: [_b]));
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB], ids: [_b]));
      expect(await idsEncolados(), isEmpty);
    });
  });

  group('perfil del vendedor: reapertura de fotos «fallido»', () {
    test('A. reabre una foto del perfil «fallido» aunque ya no forme parte del perfil, y avisa al Worker', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      await sembrar('u1', _a, origen: 'profile', refId: 'u1'); // la foto _a ya no está en el perfil
      await esperarAvisos();
      expect(avisos, 0); // crear el perfil no avisó
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b)); // no retira ninguna foto
      final s = (await colaDe('u1').doc(_a).get()).data()!;
      expect(s['estado'], 'pendiente');
      expect((s['createdAt'] as Timestamp).toDate().isAfter(DateTime(2021)), isTrue, reason: 'createdAt se actualizó');
      // La app no toca los campos del Worker: él los reinicia al reclamar la solicitud.
      expect(s['intentos'], 6);
      expect(s['ultimoError'], 'imagekit_credenciales');
      expect(s['origen'], 'profile');
      expect(s['refId'], 'u1');
      expect(s['fileId'], _a);
      await esperarAvisos();
      expect(avisos, 1);
    });

    test('B. una foto que se retira en este guardado y estaba «fallido» se reabre UNA sola vez y el lote termina bien', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a));
      await sembrar('u1', _a, origen: 'profile', refId: 'u1');
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b)); // retira _a
      expect(await idsEncolados(), [_a]);
      expect(await estadoDe('u1', _a), 'pendiente');
      expect((await colaDe('u1').doc(_a).get()).data()!['intentos'], 6);
      await esperarAvisos();
      expect(avisos, 1);
    });

    test('B2. reabrirFotosFallidas respeta «excluir»: lo excluido no se vuelve a escribir', () async {
      await sembrar('u1', _a, origen: 'profile', refId: 'u1');
      await sembrar('u1', _b, origen: 'profile', refId: 'u1');
      var batch = db.batch();
      expect(await PendingFileDeletions.reabrirFotosFallidas(db: db, batch: batch, uid: 'u1', refId: 'u1', origen: OrigenFoto.profile, excluir: [_a]), 1);
      await batch.commit();
      expect(await estadoDe('u1', _a), 'fallido');
      expect(await estadoDe('u1', _b), 'pendiente');
      batch = db.batch();
      expect(await PendingFileDeletions.reabrirFotosFallidas(db: db, batch: batch, uid: 'u1', refId: 'u1', origen: OrigenFoto.profile), 1);
      await batch.commit();
      expect(await estadoDe('u1', _a), 'pendiente');
    });

    test('C. no reabre «retenida», «enUso», «procesando», «errorTemporal», «completado» ni «rechazado»', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      const estados = ['retenida', 'enUso', 'procesando', 'errorTemporal', 'completado', 'rechazado'];
      for (final e in estados) {
        await sembrar('u1', 'foto-$e', origen: 'profile', refId: 'u1', estado: e);
      }
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      for (final e in estados) {
        final s = (await colaDe('u1').doc('foto-$e').get()).data()!;
        expect(s['estado'], e, reason: e);
        expect(s['intentos'], 6, reason: e);
        expect((s['createdAt'] as Timestamp).toDate(), DateTime(2020), reason: '$e: createdAt no cambió');
      }
      await esperarAvisos();
      expect(avisos, 0);
    });

    test('D. respeta origen, refId y propietario: no reabre solicitudes de lotes, de otro perfil ni de otra persona', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      await sembrar('u1', 'lote-mismo-refid', origen: 'lot', refId: 'u1'); // otro origen, mismo refId
      await sembrar('u1', 'otro-perfil', origen: 'profile', refId: 'otroPerfil'); // otro refId
      await colaDe('u1').doc('sin-origen').set({'fileId': 'sin-origen', 'refId': 'u1', 'estado': 'fallido'}); // sin origen
      await sembrar('u2', 'de-otra-persona', origen: 'profile', refId: 'u1'); // otra persona, mismo refId
      await sembrar('u2', 'perfil-de-u2', origen: 'profile', refId: 'u2');
      await vendedores.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b));
      expect(await estadoDe('u1', 'lote-mismo-refid'), 'fallido');
      expect(await estadoDe('u1', 'otro-perfil'), 'fallido');
      expect(await estadoDe('u1', 'sin-origen'), 'fallido');
      expect(await estadoDe('u2', 'de-otra-persona'), 'fallido');
      expect(await estadoDe('u2', 'perfil-de-u2'), 'fallido');
      await esperarAvisos();
      expect(avisos, 0, reason: 'no se reabrió nada: no hay motivo para avisar');
    });

    test('E. sin fotos retiradas ni solicitudes reabiertas no se avisa al Worker', () async {
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB], ids: [_b])); // crear
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB], ids: [_b])); // sin cambios
      await vendedores.guardarPerfil(_perfil(principal: _urlA, idPrincipal: _a, galeria: [_urlB], ids: [_b], nombre: 'Otro nombre')); // solo texto
      await esperarAvisos();
      expect(avisos, 0);
      expect(await idsEncolados(), isEmpty);
    });

    test('F. si el aviso al Worker falla (asíncrono o síncrono), el perfil y la cola quedan guardados', () async {
      final fallos = <Future<void> Function()>[
        () async => throw StateError('sin red'),
        () => throw StateError('fallo síncrono'),
      ];
      for (var i = 0; i < fallos.length; i++) {
        final repo = SellerRepository(db: db, alRetirarFotos: fallos[i]);
        final foto = 'foto-fallida-$i';
        await repo.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b, nombre: 'Marca $i'));
        await sembrar('u1', foto, origen: 'profile', refId: 'u1');
        await repo.guardarPerfil(_perfil(principal: _urlB, idPrincipal: _b, nombre: 'Marca nueva $i'));
        await esperarAvisos(); // el aviso ya falló: no debe haber errores sin capturar ni deshacer nada
        expect((await db.collection('sellerProfiles').doc('u1').get()).data()!['nombreMarca'], 'Marca nueva $i');
        expect(await estadoDe('u1', foto), 'pendiente');
      }
    });
  });

  group('ImageCleanupClient', () {
    const configurada = ImageKitConfig(
      authEndpoint: 'https://auth.example.workers.dev',
      publicKey: 'public_x',
      cleanupEndpoint: 'https://cleanup.example.workers.dev',
    );

    test('envía el token de Firebase y NINGÚN fileId', () async {
      late http.Request recibida;
      final cliente = ImageCleanupClient(
        client: MockClient((r) async {
          recibida = r;
          return http.Response('{}', 200);
        }),
        tokenProvider: () async => 'token-firebase',
        config: configurada,
      );
      await cliente.procesarCola();
      expect(recibida.url.toString(), 'https://cleanup.example.workers.dev');
      expect(recibida.method, 'POST');
      expect(recibida.headers['Authorization'], 'Bearer token-firebase');
      expect(recibida.body, isEmpty);
    });

    test('sin endpoint configurado no hace ninguna petición', () async {
      var llamadas = 0;
      final cliente = ImageCleanupClient(
        client: MockClient((r) async {
          llamadas++;
          return http.Response('{}', 200);
        }),
        tokenProvider: () async => 'token',
        config: const ImageKitConfig(authEndpoint: 'https://a.example', publicKey: 'p'),
      );
      expect(cliente.configurado, isFalse);
      await cliente.procesarCola();
      expect(llamadas, 0);
    });

    test('sin sesión, con error de red o con 500 no lanza nunca', () async {
      final sinSesion = ImageCleanupClient(client: MockClient((r) async => http.Response('{}', 200)), tokenProvider: () async => null, config: configurada);
      await sinSesion.procesarCola();
      final conRed = ImageCleanupClient(client: MockClient((r) async => throw http.ClientException('sin red')), tokenProvider: () async => 't', config: configurada);
      await conRed.procesarCola();
      final con500 = ImageCleanupClient(client: MockClient((r) async => http.Response('boom', 500)), tokenProvider: () async => 't', config: configurada);
      await con500.procesarCola();
    });

    test('exige HTTPS', () {
      final http1 = ImageCleanupClient(
        config: const ImageKitConfig(authEndpoint: 'https://a.example', publicKey: 'p', cleanupEndpoint: 'http://inseguro.example'),
      );
      expect(http1.configurado, isFalse);
    });
  });

  test('PendingFileDeletions.ref apunta a users/{uid}/pendingFileDeletions/{fileId}', () {
    expect(PendingFileDeletions.ref(db, 'u1', _a).path, 'users/u1/pendingFileDeletions/$_a');
  });
}
