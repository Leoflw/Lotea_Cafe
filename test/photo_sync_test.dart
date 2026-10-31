import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/repositories/image_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/services/photo_sync.dart';

const _config = ImageKitConfig(authEndpoint: 'https://worker.example.workers.dev', publicKey: 'public_test=');
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 3)]);

/// Repositorio cuyo ImageKit falla para los archivos de [fallan] (por orden de
/// llegada, empezando en 1) y acepta los demás.
ImageRepository _repo({Set<int> fallan = const {}, List<String>? urlsEmitidas}) {
  var subida = 0;
  final cliente = MockClient((r) async {
    if (r.url.host == 'worker.example.workers.dev') {
      return http.Response(
        jsonEncode({'token': 't${subida + 1}', 'expire': 1, 'signature': 's', 'folder': '/f', 'fileName': 'a.jpg'}),
        200,
      );
    }
    subida++;
    if (fallan.contains(subida)) throw const SocketException('sin red');
    final url = 'https://ik.imagekit.io/demo/f/foto_$subida.jpg';
    urlsEmitidas?.add(url);
    return http.Response(jsonEncode({'fileId': 'id_$subida', 'url': url}), 200);
  });
  return ImageRepository(client: cliente, tokenProvider: () async => 'tok', config: _config, intentos: 1);
}

Future<List<String>> _archivos(int n) async {
  final dir = await Directory.systemTemp.createTemp('lotea_sync');
  addTearDown(() => dir.delete(recursive: true));
  return [
    for (var i = 0; i < n; i++) (File('${dir.path}/f$i.jpg')..writeAsBytesSync(_jpeg)).path,
  ];
}

void main() {
  test('sube solo las locales y conserva las URLs ya subidas, en orden', () async {
    final locales = await _archivos(2);
    const previa = 'https://ik.imagekit.io/demo/f/previa.jpg';
    final ids = {previa: 'id_previa'};
    final r = await PhotoSync.sincronizar(
      repo: _repo(),
      proposito: ImagePurpose.lot,
      fotos: [locales[0], previa, locales[1]],
      idsPorUrl: ids,
    );
    expect(r.urls, [
      'https://ik.imagekit.io/demo/f/foto_1.jpg',
      previa,
      'https://ik.imagekit.io/demo/f/foto_2.jpg',
    ]);
    expect(r.fileIds, ['id_1', 'id_previa', 'id_2']);
    expect(r.completo, isTrue);
    expect(ids['https://ik.imagekit.io/demo/f/foto_1.jpg'], 'id_1');
  });

  test('alSubir entrega la URL de cada foto apenas se sube (para no repetirla al reintentar)', () async {
    final locales = await _archivos(2);
    final vistas = <String, String>{};
    await PhotoSync.sincronizar(
      repo: _repo(),
      proposito: ImagePurpose.lot,
      fotos: locales,
      idsPorUrl: {},
      alSubir: (local, url) => vistas[local] = url,
    );
    expect(vistas.keys, locales);
    expect(vistas.values.every((u) => u.startsWith('https://')), isTrue);
  });

  test('con continuarSiFalla una foto fallida NO entra en las URLs y se reporta', () async {
    final locales = await _archivos(3);
    final r = await PhotoSync.sincronizar(
      repo: _repo(fallan: {2}),
      proposito: ImagePurpose.lot,
      fotos: locales,
      idsPorUrl: {},
      continuarSiFalla: true,
    );
    expect(r.urls.length, 2);
    expect(r.fileIds.length, 2);
    expect(r.completo, isFalse);
    expect(r.fallidas.single.ruta, locales[1]);
    expect(r.fallidas.single.error.tipo, RepoErrorKind.sinConexion);
    // Ninguna ruta local se cuela como si fuera una foto disponible.
    expect(r.urls.any(PhotoSync.esLocal), isFalse);
  });

  test('sin continuarSiFalla el primer fallo se relanza (publicación y perfil)', () async {
    final locales = await _archivos(2);
    await expectLater(
      PhotoSync.sincronizar(repo: _repo(fallan: {1}), proposito: ImagePurpose.profile, fotos: locales, idsPorUrl: {}),
      throwsA(isA<RepoException>()),
    );
  });

  test('si todas fallan, no queda ninguna URL', () async {
    final locales = await _archivos(2);
    final r = await PhotoSync.sincronizar(
      repo: _repo(fallan: {1, 2}),
      proposito: ImagePurpose.lot,
      fotos: locales,
      idsPorUrl: {},
      continuarSiFalla: true,
    );
    expect(r.urls, isEmpty);
    expect(r.fallidas.length, 2);
  });

  test('los recursos de marca (assets/) no se suben ni se guardan', () async {
    final r = await PhotoSync.sincronizar(
      repo: _repo(),
      proposito: ImagePurpose.lot,
      fotos: ['assets/branding/lotea_cafe_symbol.png'],
      idsPorUrl: {},
    );
    expect(r.urls, isEmpty);
  });
}
