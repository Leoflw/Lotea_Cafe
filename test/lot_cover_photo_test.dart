import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/repositories/image_repository.dart';
import 'package:lotea_cafe/repositories/interest_request_repository.dart';
import 'package:lotea_cafe/services/photo_sync.dart';
import 'package:lotea_cafe/widgets/app_image.dart';

const _a = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_a.jpg';
const _b = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_b.jpg';
const _c = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_c.jpg';

CoffeeLot _lote(List<String> fotos, {String id = 'lot1', List<String> ids = const []}) => CoffeeLot(
      id: id,
      sellerId: 'u1',
      nombre: 'ffff',
      variedades: const ['Caturra'],
      proceso: 'Natural',
      precioCOP: 555,
      fotos: fotos,
      fotosStoragePaths: ids,
      sellerNombreMarca: 'dyd',
      departamento: 'Antioquia',
      region: 'Antioquia',
      estado: EstadoLote.publicado,
    );

ImageRepository _repoSinUso() => ImageRepository(
      client: MockClient((_) async => http.Response('no debería llamarse', 500)),
      tokenProvider: () async => 'tok',
      config: const ImageKitConfig(authEndpoint: 'https://worker.example.workers.dev', publicKey: 'public_x='),
    );

Widget _app(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));

void main() {
  group('foto principal de un café', () {
    test('es la PRIMERA foto con URL remota de su propio documento', () {
      expect(_lote([_a, _b]).fotoPrincipal, _a);
      expect(_lote([_b, _a]).fotoPrincipal, _b);
    });

    test('una entrada vacía o una ruta local no se usa como portada', () {
      expect(_lote(['', '/data/user/0/cache/foto.jpg', _c, _a]).fotoPrincipal, _c);
    });

    test('sin fotos (o sin ninguna válida) no hay portada: estado vacío, nunca una URL inventada', () {
      expect(_lote([]).fotoPrincipal, isNull);
      expect(_lote([]).tieneFoto, isFalse);
      expect(_lote(['', 'no-es-url']).fotoPrincipal, isNull);
    });

    test('la galería del detalle solo incluye URLs remotas, en el orden guardado', () {
      expect(_lote(['', _a, '/local.jpg', _b]).fotosRemotas, [_a, _b]);
    });

    test('dos cafés distintos conservan cada uno SU portada', () {
      final uno = _lote([_a], id: 'lot1');
      final dos = _lote([_b], id: 'lot2');
      expect(uno.fotoPrincipal, _a);
      expect(dos.fotoPrincipal, _b);
    });

    test('la solicitud de interés copia la portada del café correcto (o null si no tiene)', () async {
      final db = FakeFirebaseFirestore();
      final repo = InterestRequestRepository(db: db);
      const comprador = AppUser(uid: 'b1', email: 'b@x.co', nombre: 'juan', rol: UserRole.comprador);
      await repo.crear(comprador: comprador, lote: _lote(['', _b, _a], id: 'lot1'));
      await repo.crear(comprador: comprador, lote: _lote([], id: 'lot2'));
      final s1 = (await db.collection('interestRequests').doc('b1_lot1').get()).data()!;
      final s2 = (await db.collection('interestRequests').doc('b1_lot2').get()).data()!;
      expect(s1['loteFoto'], _b);
      expect(s2['loteFoto'], isNull);
    });
  });

  group('relación entre fotos, URL y fileId al quitar o reordenar', () {
    test('quitar una foto conserva el fileId de cada una de las demás', () async {
      final ids = {_a: 'file-a', _b: 'file-b', _c: 'file-c'};
      // El formulario quitó la foto B.
      final r = await PhotoSync.sincronizar(repo: _repoSinUso(), proposito: ImagePurpose.lot, fotos: [_a, _c], idsPorUrl: ids);
      expect(r.urls, [_a, _c]);
      expect(r.fileIds, ['file-a', 'file-c']);
    });

    test('«hacer principal» reordena las URLs y los fileId juntos', () async {
      final ids = {_a: 'file-a', _b: 'file-b', _c: 'file-c'};
      final r = await PhotoSync.sincronizar(repo: _repoSinUso(), proposito: ImagePurpose.lot, fotos: [_c, _a, _b], idsPorUrl: ids);
      expect(r.urls, [_c, _a, _b]);
      expect(r.fileIds, ['file-c', 'file-a', 'file-b']);
    });

    test('quitar todas deja listas vacías del mismo tamaño', () async {
      final r = await PhotoSync.sincronizar(repo: _repoSinUso(), proposito: ImagePurpose.lot, fotos: [], idsPorUrl: {_a: 'file-a'});
      expect(r.urls, isEmpty);
      expect(r.fileIds, isEmpty);
    });
  });

  group('AppImage: estados sin imagen o con error', () {
    testWidgets('un café sin foto muestra el estado vacío, sin desbordar una tarjeta pequeña', (tester) async {
      await tester.pumpWidget(_app(const AppImage(path: null, width: 44, height: 44, ampliable: false)));
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una ruta inválida no rompe la tarjeta: queda el placeholder', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(_app(const SizedBox(width: 300, height: 200, child: AppImage(path: 'no-es-una-url', ampliable: false))));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      expect(find.text('Sin fotografía'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una URL de ImageKit que falla en una miniatura de 46 px no desborda', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(_app(const AppImage(path: _a, width: 46, height: 46, ampliable: false)));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
