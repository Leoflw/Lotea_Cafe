import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/discover_filters.dart';
import 'package:lotea_cafe/models/seller_profile.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/image_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/services/photo_sync.dart';
import 'package:lotea_cafe/utils/lot_publish_policy.dart';

const _urlA = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_a.jpg';
const _urlB = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_b.jpg';

CoffeeLot _lote({
  List<String> fotos = const [],
  List<String> ids = const [],
  EstadoLote estado = EstadoLote.borrador,
  String nombre = 'Caturra Lavado',
}) =>
    CoffeeLot(
      id: '',
      sellerId: 'u1',
      nombre: nombre,
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

Matcher _validacion() => throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion));

void main() {
  late FakeFirebaseFirestore db;
  late CoffeeLotRepository lotes;

  setUp(() {
    db = FakeFirebaseFirestore();
    lotes = CoffeeLotRepository(db: db);
  });

  Future<Map<String, dynamic>> leer(String id) async => (await db.collection('coffeeLots').doc(id).get()).data()!;

  group('persistencia de la URL de ImageKit en Firestore', () {
    test('al publicar se guardan las URLs y los fileId en el documento del lote', () async {
      final id = await lotes.guardarLote(_lote(fotos: [_urlA, _urlB], ids: ['file-a', 'file-b'], estado: EstadoLote.publicado));
      final doc = await leer(id);
      expect(doc['fotos'], [_urlA, _urlB]);
      expect(doc['fotosStoragePaths'], ['file-a', 'file-b']);
      expect(doc['estado'], 'publicado');
    });

    test('el documento solo contiene URLs: ni bytes ni Base64', () async {
      final id = await lotes.guardarLote(_lote(fotos: [_urlA], ids: ['file-a'], estado: EstadoLote.publicado));
      final doc = await leer(id);
      void revisar(Object? v) {
        if (v is String) {
          expect(
              v.length,
              lessThan(600),
              reason: 'cadena sospechosamente larga (${v.length} caracteres)',
            );
          expect(v.startsWith('data:'), isFalse);
        } else if (v is Uint8List || v is Blob) {
          fail('no se deben guardar bytes en Firestore');
        } else if (v is Iterable) {
          v.forEach(revisar);
        } else if (v is Map) {
          v.values.forEach(revisar);
        }
      }

      doc.values.forEach(revisar);
      expect(jsonEncode(doc.map((k, v) => MapEntry(k, v is Timestamp ? v.seconds : v))).toLowerCase(), isNot(contains('base64')));
    });

    test('al editar y volver a guardar se actualizan las fotos del mismo documento', () async {
      final id = await lotes.guardarLote(_lote(fotos: [_urlA], ids: ['file-a'], estado: EstadoLote.publicado));
      await lotes.guardarLote(_lote(fotos: [_urlA, _urlB], ids: ['file-a', 'file-b'], estado: EstadoLote.publicado), idExistente: id);
      expect((await leer(id))['fotos'], [_urlA, _urlB]);
      expect((await db.collection('coffeeLots').get()).docs.length, 1);
    });

    test('el modelo lee las fotos guardadas', () async {
      final id = await lotes.guardarLote(_lote(fotos: [_urlA], ids: ['file-a'], estado: EstadoLote.publicado));
      final lote = (await lotes.obtener(id))!;
      expect(lote.fotos, [_urlA]);
      expect(lote.fotosStoragePaths, ['file-a']);
      expect(lote.tieneFoto, isTrue);
    });

    test('el perfil del vendedor guarda la URL y el fileId de su foto y su galería', () async {
      final repo = SellerRepository(db: db);
      await repo.guardarPerfil(const SellerProfile(
        id: 'u1',
        usuarioId: 'u1',
        nombreMarca: 'Finca La Esperanza',
        fincaPrincipal: 'La Esperanza',
        fotoPrincipal: 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/profile/profile_p.jpg',
        fotoPrincipalStoragePath: 'file-p',
        galeria: [_urlA],
        galeriaStoragePaths: ['file-g1'],
        region: 'Huila',
        departamento: 'Huila',
      ));
      final p = (await repo.obtener('u1'))!;
      expect(p.fotoPrincipal, startsWith('https://ik.imagekit.io/'));
      expect(p.fotoPrincipalStoragePath, 'file-p');
      expect(p.galeria, [_urlA]);
      expect(p.galeriaStoragePaths, ['file-g1']);
    });
  });

  group('borradores y publicación', () {
    test('guardar un borrador SIN fotos funciona', () async {
      final id = await lotes.guardarLote(_lote());
      final doc = await leer(id);
      expect(doc['estado'], 'borrador');
      expect(doc['fotos'], isEmpty);
      expect(doc['fechaPublicacion'], isNull);
    });

    test('publicar con una imagen subida correctamente funciona y fija la fecha de publicación', () async {
      final id = await lotes.guardarLote(_lote(fotos: [_urlA], ids: ['file-a'], estado: EstadoLote.publicado));
      final doc = await leer(id);
      expect(doc['estado'], 'publicado');
      expect(doc['fechaPublicacion'], isNotNull);
    });

    test('publicar SIN fotos se rechaza y no crea ningún documento', () async {
      await expectLater(lotes.guardarLote(_lote(estado: EstadoLote.publicado)), _validacion());
      expect((await db.collection('coffeeLots').get()).docs, isEmpty);
    });

    test('una ruta local (subida fallida) no cuenta como foto: no se puede publicar con ella', () async {
      await expectLater(
        lotes.guardarLote(_lote(fotos: ['/data/user/0/com.loteacafe/cache/foto.jpg'], estado: EstadoLote.publicado)),
        _validacion(),
      );
      expect((await db.collection('coffeeLots').get()).docs, isEmpty);
    });

    test('publicar un borrador existente sin fotos también se rechaza y lo deja como estaba', () async {
      final id = await lotes.guardarLote(_lote());
      await expectLater(lotes.guardarLote(_lote(estado: EstadoLote.publicado), idExistente: id), _validacion());
      expect((await leer(id))['estado'], 'borrador');
    });

    test('flujo completo: un borrador con subida fallida se guarda SIN foto disponible', () async {
      final dir = await Directory.systemTemp.createTemp('lotea_fallo');
      addTearDown(() => dir.delete(recursive: true));
      final archivo = File('${dir.path}/foto.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

      final sinRed = ImageRepository(
        client: MockClient((_) async => throw const SocketException('sin red')),
        tokenProvider: () async => 'tok',
        config: const ImageKitConfig(authEndpoint: 'https://worker.example.workers.dev', publicKey: 'public_x='),
        intentos: 1,
      );
      final sync = await PhotoSync.sincronizar(
        repo: sinRed,
        proposito: ImagePurpose.lot,
        fotos: [archivo.path],
        idsPorUrl: {},
        continuarSiFalla: true,
      );
      expect(sync.fallidas.length, 1);
      // Para un borrador la política deja continuar; para publicar, no.
      expect(LotPublishPolicy.motivoBloqueo(publicar: false, fotosSubidas: sync.urls.length, fotosFallidas: 1), isNull);
      expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: sync.urls.length, fotosFallidas: 1), isNotNull);

      final id = await lotes.guardarLote(_lote(fotos: sync.urls, ids: sync.fileIds));
      final lote = (await lotes.obtener(id))!;
      expect(lote.fotos, isEmpty);
      expect(lote.tieneFoto, isFalse);
      expect(lote.publicado, isFalse);
    });

    test('flujo completo: con una subida exitosa el lote se publica con la URL devuelta por ImageKit', () async {
      final dir = await Directory.systemTemp.createTemp('lotea_ok');
      addTearDown(() => dir.delete(recursive: true));
      final archivo = File('${dir.path}/foto.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

      final repoImg = ImageRepository(
        client: MockClient((r) async {
          if (r.url.host == 'worker.example.workers.dev') {
            return http.Response(jsonEncode({'token': 't', 'expire': 1, 'signature': 's', 'folder': '/f', 'fileName': 'a.jpg'}), 200);
          }
          return http.Response(jsonEncode({'fileId': 'file-nuevo', 'url': _urlA}), 200);
        }),
        tokenProvider: () async => 'tok',
        config: const ImageKitConfig(authEndpoint: 'https://worker.example.workers.dev', publicKey: 'public_x='),
      );
      final sync = await PhotoSync.sincronizar(repo: repoImg, proposito: ImagePurpose.lot, fotos: [archivo.path], idsPorUrl: {});
      expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: sync.urls.length, fotosFallidas: sync.fallidas.length), isNull);

      final id = await lotes.guardarLote(_lote(fotos: sync.urls, ids: sync.fileIds, estado: EstadoLote.publicado));
      final doc = await leer(id);
      expect(doc['fotos'], [_urlA]);
      expect(doc['fotosStoragePaths'], ['file-nuevo']);
      expect(doc['estado'], 'publicado');
    });
  });

  group('catálogo', () {
    test('el catálogo devuelve solo lotes publicados con sus URLs de ImageKit; los borradores no aparecen', () async {
      await lotes.guardarLote(_lote(nombre: 'Publicado', fotos: [_urlA], ids: ['a'], estado: EstadoLote.publicado));
      await lotes.guardarLote(_lote(nombre: 'Borrador sin foto'));
      final pagina = await lotes.consultarCatalogo(orden: DiscoverSort.relevancia);
      expect(pagina.lotes.map((l) => l.nombre), ['Publicado']);
      expect(pagina.lotes.single.fotos.single, _urlA);
      expect(pagina.lotes.single.tieneFoto, isTrue);
    });
  });
}
