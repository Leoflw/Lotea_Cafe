import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lotea_cafe/config/imagekit_config.dart';
import 'package:lotea_cafe/repositories/image_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';

const _config = ImageKitConfig(authEndpoint: 'https://worker.example.workers.dev', publicKey: 'public_test=');
const _workerUrl = 'https://worker.example.workers.dev';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(200, 7)]);

Map<String, dynamic> _autorizacion() => {
      'token': 'tok-1',
      'expire': 1800000600,
      'signature': 'firma-hex',
      'publicKey': 'public_test=',
      'folder': '/lotea-cafe/users/u1/lots',
      'fileName': 'lot_1_abcd1234.jpg',
      'maxBytes': 5242880,
    };

Map<String, dynamic> _respuestaImageKit() => {
      'fileId': 'file-123',
      'name': 'lot_1_abcd1234_x.jpg',
      'url': 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_1_abcd1234_x.jpg',
      'filePath': '/lotea-cafe/users/u1/lots/lot_1_abcd1234_x.jpg',
      'size': 207,
    };

http.Response _json(int estado, Object cuerpo) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json'});

/// Cliente falso: [alWorker] y [alImageKit] responden cada llamada.
class _Servidor {
  final List<http.BaseRequest> peticiones = [];
  final List<String> cuerpos = [];
  FutureOr<http.Response> Function(http.Request r) alWorker = (_) => _json(200, _autorizacion());
  FutureOr<http.Response> Function(http.Request r) alImageKit = (_) => _json(200, _respuestaImageKit());

  int get llamadasWorker => peticiones.where((r) => r.url.toString().startsWith(_workerUrl)).length;
  int get llamadasImageKit => peticiones.where((r) => r.url.host == 'upload.imagekit.io').length;

  MockClient get cliente => MockClient((r) async {
        peticiones.add(r);
        // El cuerpo de la subida a ImageKit es multipart con los bytes binarios de la imagen:
        // `r.body` los decodificaría como UTF-8 estricto y lanzaría FormatException.
        // Se leen los bytes y se decodifica de forma tolerante solo para inspeccionar los
        // campos de texto (cabeceras y nombres de campo, que son ASCII).
        cuerpos.add(utf8.decode(r.bodyBytes, allowMalformed: true));
        return r.url.toString().startsWith(_workerUrl) ? await alWorker(r) : await alImageKit(r);
      });
}

ImageRepository _repo(
  _Servidor s, {
  TokenProvider? token,
  ImageKitConfig config = _config,
  List<Duration>? esperas,
  int intentos = 3,
}) =>
    ImageRepository(
      client: s.cliente,
      tokenProvider: token ?? () async => 'firebase-id-token',
      config: config,
      intentos: intentos,
      dormir: (d) async => esperas?.add(d),
    );

Matcher _falla(RepoErrorKind tipo) => throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', tipo));

void main() {
  group('autorización de una subida', () {
    test('pide la autorización al Worker con el token de Firebase y sube a ImageKit', () async {
      final s = _Servidor();
      final r = await _repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg);

      // 1) Worker: POST con Bearer y datos de la imagen (sin UID: lo saca el Worker del token).
      final aut = s.peticiones.first as http.Request;
      expect(aut.method, 'POST');
      expect(aut.url.toString(), _workerUrl);
      expect(aut.headers['Authorization'], 'Bearer firebase-id-token');
      expect(jsonDecode(aut.body), {'purpose': 'lot', 'contentType': 'image/jpeg', 'size': _jpeg.length});

      // 2) ImageKit: HTTPS multipart/form-data con los parámetros autorizados.
      final subida = s.peticiones.last;
      expect(subida.url.toString(), 'https://upload.imagekit.io/api/v1/files/upload');
      expect(subida.method, 'POST');
      expect(subida.headers['content-type'], startsWith('multipart/form-data; boundary='));
      final cuerpo = s.cuerpos.last;
      for (final esperado in [
        'name="publicKey"', 'public_test=',
        'name="token"', 'tok-1',
        'name="signature"', 'firma-hex',
        'name="expire"', '1800000600',
        'name="folder"', '/lotea-cafe/users/u1/lots',
        'name="fileName"', 'lot_1_abcd1234.jpg',
        'name="file"', 'content-type: image/jpeg',
      ]) {
        expect(cuerpo, contains(esperado), reason: esperado);
      }
      // La clave privada no existe en la app: ningún campo de la petición la menciona.
      expect(cuerpo.toLowerCase(), isNot(contains('privatekey')));

      // 3) Devuelve URL y fileId.
      expect(r.url, startsWith('https://ik.imagekit.io/'));
      expect(r.fileId, 'file-123');
      expect(r.filePath, '/lotea-cafe/users/u1/lots/lot_1_abcd1234_x.jpg');
    });

    test('el propósito «profile» llega al Worker', () async {
      final s = _Servidor();
      await _repo(s).subirBytes(proposito: ImagePurpose.profile, bytes: _jpeg);
      expect(jsonDecode((s.peticiones.first as http.Request).body)['purpose'], 'profile');
    });

    test('informa el progreso por etapas hasta 1', () async {
      final s = _Servidor();
      final valores = <double>[];
      await _repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg, alProgresar: valores.add);
      expect(valores.first, 0);
      expect(valores.last, 1);
      expect(valores, orderedEquals([...valores]..sort()));
    });

    test('sube un archivo local (File) leyendo sus bytes', () async {
      final dir = await Directory.systemTemp.createTemp('lotea_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/foto.jpg')..writeAsBytesSync(_jpeg);
      final s = _Servidor();
      final r = await _repo(s).subir(proposito: ImagePurpose.lot, archivo: f);
      expect(r.fileId, 'file-123');
    });

    test('un archivo que no existe da un error entendible', () async {
      final s = _Servidor();
      await expectLater(
        _repo(s).subir(proposito: ImagePurpose.lot, archivo: File('/no/existe/foto.jpg')),
        _falla(RepoErrorKind.otro),
      );
      expect(s.peticiones, isEmpty);
    });
  });

  group('usuarios no autenticados', () {
    test('sin sesión ni siquiera se llama al Worker', () async {
      final s = _Servidor();
      await expectLater(
        _repo(s, token: () async => null).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg),
        _falla(RepoErrorKind.sinSesion),
      );
      expect(s.peticiones, isEmpty);
    });

    test('un token vacío se trata como sin sesión', () async {
      final s = _Servidor();
      await expectLater(
        _repo(s, token: () async => '').subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg),
        _falla(RepoErrorKind.sinSesion),
      );
    });

    test('si el Worker responde 401 (token no válido/expirado) → sinSesion, sin reintentos ni subida', () async {
      final s = _Servidor()..alWorker = (_) => _json(401, {'error': 'Sesión no válida'});
      await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.sinSesion));
      expect(s.llamadasWorker, 1);
      expect(s.llamadasImageKit, 0);
    });

    test('si el Worker responde 403 (rol no permitido) → sinPermisos con su mensaje', () async {
      final s = _Servidor()..alWorker = (_) => _json(403, {'error': 'Solo las cuentas de vendedor pueden subir estas fotos.'});
      await expectLater(
        _repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.sinPermisos).having((e) => e.mensaje, 'mensaje', contains('vendedor'))),
      );
      expect(s.llamadasImageKit, 0);
    });
  });

  group('validación de tipo y tamaño antes de tocar la red', () {
    test('un GIF se rechaza sin ninguna petición', () async {
      final s = _Servidor();
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0]);
      await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: gif), _falla(RepoErrorKind.validacion));
      expect(s.peticiones, isEmpty);
    });

    test('una imagen de más de 5 MB se rechaza sin ninguna petición', () async {
      final s = _Servidor();
      final grande = Uint8List(ImageRepository.maxBytes + 1)..setRange(0, 4, [0xFF, 0xD8, 0xFF, 0xE0]);
      await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: grande), _falla(RepoErrorKind.validacion));
      expect(s.peticiones, isEmpty);
    });

    test('si el Worker rechaza tipo o tamaño (415/413/400) no se reintenta', () async {
      for (final estado in [400, 413, 415]) {
        final s = _Servidor()..alWorker = (_) => _json(estado, {'error': 'No cumple'});
        await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.validacion), reason: '$estado');
        expect(s.llamadasWorker, 1, reason: '$estado');
      }
    });

    test('si ImageKit rechaza la imagen (400) se informa sin reintentar', () async {
      final s = _Servidor()..alImageKit = (_) => _json(400, {'message': 'Archivo no válido'});
      await expectLater(
        _repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg),
        throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion).having((e) => e.mensaje, 'mensaje', 'Archivo no válido')),
      );
      expect(s.llamadasImageKit, 1);
    });
  });

  group('fallos de red', () {
    test('sin conexión: reintenta 3 veces con espera creciente y termina en sinConexion', () async {
      final s = _Servidor()..alWorker = (_) => throw const SocketException('sin red');
      final esperas = <Duration>[];
      await expectLater(
        _repo(s, esperas: esperas).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg),
        _falla(RepoErrorKind.sinConexion),
      );
      expect(s.llamadasWorker, 3);
      expect(esperas, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('un error de cliente HTTP también es «sin conexión»', () async {
      final s = _Servidor()..alImageKit = (_) => throw http.ClientException('connection reset');
      await expectLater(_repo(s, intentos: 1).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.sinConexion));
    });

    test('si el primer intento falla y el segundo funciona, la subida termina bien con una autorización NUEVA', () async {
      var n = 0;
      final s = _Servidor()
        ..alImageKit = (_) {
          n++;
          if (n == 1) throw const SocketException('corte');
          return _json(200, _respuestaImageKit());
        };
      final r = await _repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg);
      expect(r.fileId, 'file-123');
      expect(s.llamadasWorker, 2, reason: 'cada intento pide una autorización nueva');
      expect(s.llamadasImageKit, 2);
    });

    test('un 503 o un 429 se reintentan; un 500 persistente acaba en sinConexion', () async {
      for (final estado in [429, 500, 503]) {
        final s = _Servidor()..alWorker = (_) => _json(estado, {'error': 'ocupado'});
        await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.sinConexion), reason: '$estado');
        expect(s.llamadasWorker, 3, reason: '$estado');
      }
    });

    test('un tiempo de espera agotado se informa como sinConexion', () async {
      final s = _Servidor()..alWorker = (_) => throw TimeoutException('lento');
      await expectLater(_repo(s, intentos: 1).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.sinConexion));
    });

    test('esRecuperable permite a la interfaz ofrecer «Reintentar»', () async {
      final s = _Servidor()..alWorker = (_) => throw const SocketException('x');
      try {
        await _repo(s, intentos: 1).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg);
        fail('debía fallar');
      } on RepoException catch (e) {
        expect(e.esRecuperable, isTrue);
      }
    });
  });

  group('respuestas inesperadas y configuración', () {
    test('una autorización incompleta del Worker no se usa', () async {
      final s = _Servidor()..alWorker = (_) => _json(200, {'token': 'x'});
      await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.otro));
      expect(s.llamadasImageKit, 0);
    });

    test('una respuesta de ImageKit sin URL https o sin fileId se rechaza', () async {
      for (final cuerpo in [
        {'fileId': 'a', 'url': 'http://ik.imagekit.io/x.jpg'},
        {'url': 'https://ik.imagekit.io/x.jpg'},
        {'fileId': '', 'url': 'https://ik.imagekit.io/x.jpg'},
      ]) {
        final s = _Servidor()..alImageKit = (_) => _json(200, cuerpo);
        await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.otro));
      }
    });

    test('un cuerpo que no es JSON no rompe la app', () async {
      final s = _Servidor()..alWorker = (_) => http.Response('<html>', 200);
      await expectLater(_repo(s).subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.otro));
    });

    test('sin configurar (endpoint o public key vacíos, o endpoint no HTTPS) → configuracionPendiente', () async {
      for (final c in [
        const ImageKitConfig(authEndpoint: '', publicKey: ''),
        const ImageKitConfig(authEndpoint: _workerUrl, publicKey: ''),
        const ImageKitConfig(authEndpoint: 'http://inseguro.example.com', publicKey: 'public_x='),
      ]) {
        final s = _Servidor();
        final repo = _repo(s, config: c);
        expect(repo.configurado, isFalse);
        await expectLater(repo.subirBytes(proposito: ImagePurpose.lot, bytes: _jpeg), _falla(RepoErrorKind.configuracionPendiente));
        expect(s.peticiones, isEmpty);
      }
    });
  });
}
