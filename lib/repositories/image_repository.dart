import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/imagekit_config.dart';
import '../utils/image_validation.dart';
import 'repo_exception.dart';

/// Para qué se sube la foto. El Worker decide la carpeta de ImageKit y exige
/// el rol adecuado según este valor; el cliente nunca elige la carpeta.
enum ImagePurpose {
  lot,
  profile;

  String get wire => name;
}

/// Resultado de una subida. En Firestore se guardan [url] (campo `fotos`,
/// `fotoPrincipal` o `galeria`) y [fileId] (en los campos paralelos
/// `*StoragePaths`, que desde la migración contienen el `fileId` de ImageKit).
/// Nunca se guardan bytes ni Base64.
class UploadedImage {
  final String url;
  final String fileId;
  final String? filePath;
  final int sizeBytes;
  const UploadedImage(this.url, this.fileId, {this.filePath, this.sizeBytes = 0});
}

typedef TokenProvider = Future<String?> Function();

class _Autorizacion {
  final String token;
  final int expire;
  final String signature;
  final String folder;
  final String fileName;
  const _Autorizacion(this.token, this.expire, this.signature, this.folder, this.fileName);
}

/// Subida de imágenes a ImageKit (plan gratuito) con autorización del
/// Cloudflare Worker. Flujo de cada intento:
///
///  1. Validar tipo (JPEG/PNG/WebP) y tamaño en el dispositivo.
///  2. Pedir al Worker una autorización temporal enviando el token de
///     Firebase Authentication (el Worker lo valida y obtiene el UID de ahí).
///  3. Enviar la imagen a ImageKit por HTTPS `multipart/form-data`.
///  4. Devolver la URL y el `fileId`.
///
/// Los fallos de red, los 429 y los 5xx se reintentan (3 intentos, con espera
/// creciente) pidiendo una autorización NUEVA cada vez (cada una trae su
/// propio token único). Los demás errores no se reintentan.
class ImageRepository {
  static const maxBytes = ImageValidation.maxBytes;

  final http.Client _client;
  final TokenProvider? _tokenProvider;
  final ImageKitConfig _config;
  final int _intentos;
  final Future<void> Function(Duration) _dormir;
  final Duration _timeout;

  ImageRepository({
    http.Client? client,
    TokenProvider? tokenProvider,
    ImageKitConfig config = ImageKitConfig.fromEnvironment,
    int intentos = 3,
    Future<void> Function(Duration)? dormir,
    Duration timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider,
        _config = config,
        _intentos = intentos,
        _dormir = dormir ?? Future<void>.delayed,
        _timeout = timeout;

  bool get configurado => _config.configurado;

  Future<String?> _token() {
    final p = _tokenProvider;
    if (p != null) return p();
    // Se consulta FirebaseAuth solo al subir, no al construir el repositorio.
    return FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);
  }

  /// Sube un archivo local elegido de la galería.
  /// [alProgresar] recibe valores de 0 a 1 (por etapas: la API multipart no
  /// informa del avance byte a byte).
  Future<UploadedImage> subir({
    required ImagePurpose proposito,
    required File archivo,
    void Function(double progreso)? alProgresar,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await archivo.readAsBytes();
    } on FileSystemException catch (e) {
      throw RepoException(RepoErrorKind.otro, 'No se pudo leer la imagen seleccionada. Elígela de nuevo.', causa: e);
    }
    return subirBytes(proposito: proposito, bytes: bytes, alProgresar: alProgresar);
  }

  Future<UploadedImage> subirBytes({
    required ImagePurpose proposito,
    required Uint8List bytes,
    void Function(double progreso)? alProgresar,
  }) async {
    if (!_config.configurado) {
      throw const RepoException(
        RepoErrorKind.configuracionPendiente,
        'La subida de fotos no está configurada todavía. Revisa IMAGEKIT_SETUP.md.',
      );
    }
    final tipo = ImageValidation.validar(bytes);

    RepoException? ultimo;
    for (var intento = 1; intento <= _intentos; intento++) {
      try {
        return await _subirUnaVez(proposito, tipo, bytes, alProgresar);
      } on RepoException catch (e) {
        if (e.tipo != RepoErrorKind.sinConexion || intento == _intentos) rethrow;
        ultimo = e;
        await _dormir(Duration(seconds: 1 << (intento - 1)));
      }
    }
    throw ultimo ?? const RepoException(RepoErrorKind.otro, 'No se pudo subir la imagen.');
  }

  Future<UploadedImage> _subirUnaVez(
    ImagePurpose proposito,
    ImageType tipo,
    Uint8List bytes,
    void Function(double)? alProgresar,
  ) async {
    alProgresar?.call(0);
    final idToken = await _token();
    if (idToken == null || idToken.isEmpty) {
      throw const RepoException(RepoErrorKind.sinSesion, 'Tu sesión expiró. Inicia sesión de nuevo.');
    }
    final auth = await _autorizar(idToken, proposito, tipo, bytes.length);
    alProgresar?.call(0.3);
    final subida = await _enviar(auth, tipo, bytes);
    alProgresar?.call(1);
    return subida;
  }

  // ---- 1) Autorización (Cloudflare Worker) ----

  Future<_Autorizacion> _autorizar(String idToken, ImagePurpose proposito, ImageType tipo, int tam) async {
    final resp = await _http(() => _client.post(
          Uri.parse(_config.authEndpoint),
          headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
          body: jsonEncode({'purpose': proposito.wire, 'contentType': tipo.mime, 'size': tam}),
        ));
    if (resp.statusCode != 200) throw _errorHttp(resp, deAutorizacion: true);

    final m = _json(resp.body);
    final token = m['token'];
    final expire = m['expire'];
    final signature = m['signature'];
    final folder = m['folder'];
    final fileName = m['fileName'];
    if (token is! String || expire is! num || signature is! String || folder is! String || fileName is! String) {
      throw const RepoException(RepoErrorKind.otro, 'El servicio de autorización respondió algo inesperado.');
    }
    return _Autorizacion(token, expire.toInt(), signature, folder, fileName);
  }

  // ---- 2) Envío a ImageKit ----

  Future<UploadedImage> _enviar(_Autorizacion a, ImageType tipo, Uint8List bytes) async {
    final resp = await _http(() async {
      final req = http.MultipartRequest('POST', Uri.parse(ImageKitConfig.uploadEndpoint))
        ..fields.addAll({
          'publicKey': _config.publicKey,
          'signature': a.signature,
          'expire': '${a.expire}',
          'token': a.token,
          'fileName': a.fileName,
          'folder': a.folder,
          'useUniqueFileName': 'true',
          'isPrivateFile': 'false',
        })
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: a.fileName, contentType: MediaType.parse(tipo.mime)));
      final streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    });
    if (resp.statusCode != 200) throw _errorHttp(resp, deAutorizacion: false);

    final m = _json(resp.body);
    final url = m['url'];
    final fileId = m['fileId'];
    if (url is! String || !url.startsWith('https://') || fileId is! String || fileId.isEmpty) {
      throw const RepoException(RepoErrorKind.otro, 'ImageKit respondió algo inesperado. Inténtalo de nuevo.');
    }
    final size = m['size'];
    final filePath = m['filePath'];
    return UploadedImage(url, fileId, filePath: filePath is String ? filePath : null, sizeBytes: size is num ? size.toInt() : bytes.length);
  }

  // ---- Utilidades ----

  /// Ejecuta una petición traduciendo los fallos de red a `sinConexion`.
  Future<http.Response> _http(Future<http.Response> Function() peticion) async {
    try {
      return await peticion().timeout(_timeout);
    } on TimeoutException catch (e) {
      throw RepoException(RepoErrorKind.sinConexion, 'La subida tardó demasiado. Revisa tu internet e inténtalo de nuevo.', causa: e);
    } on SocketException catch (e) {
      throw RepoException(RepoErrorKind.sinConexion, 'Sin conexión. Revisa tu internet e inténtalo de nuevo.', causa: e);
    } on http.ClientException catch (e) {
      throw RepoException(RepoErrorKind.sinConexion, 'Sin conexión. Revisa tu internet e inténtalo de nuevo.', causa: e);
    }
  }

  Map<String, dynamic> _json(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
    } on FormatException {
      // cae al error de abajo
    }
    throw const RepoException(RepoErrorKind.otro, 'Respuesta inesperada del servicio de imágenes.');
  }

  String? _mensajeDe(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map) {
        final m = d['error'] ?? d['message'];
        if (m is String && m.isNotEmpty && m.length <= 200) return m;
      }
    } on FormatException {
      // sin cuerpo JSON
    }
    return null;
  }

  RepoException _errorHttp(http.Response r, {required bool deAutorizacion}) {
    final s = r.statusCode;
    final detalle = _mensajeDe(r);
    if (s == 429 || s >= 500) {
      return RepoException(RepoErrorKind.sinConexion, 'El servicio de imágenes está ocupado. Inténtalo de nuevo en un momento.', causa: r);
    }
    if (deAutorizacion) {
      if (s == 401) return RepoException(RepoErrorKind.sinSesion, 'Tu sesión expiró. Inicia sesión de nuevo.', causa: r);
      if (s == 403) {
        return RepoException(RepoErrorKind.sinPermisos, detalle ?? 'Tu cuenta no puede subir esta foto.', causa: r);
      }
      if (s == 400 || s == 413 || s == 415 || s == 422) {
        return RepoException(RepoErrorKind.validacion, detalle ?? 'La imagen no cumple los requisitos (JPEG, PNG o WebP, máximo 5 MB).', causa: r);
      }
    } else if (s == 400 || s == 413 || s == 422) {
      return RepoException(RepoErrorKind.validacion, detalle ?? 'ImageKit no aceptó la imagen.', causa: r);
    }
    return RepoException(RepoErrorKind.otro, 'No se pudo subir la imagen (código $s).', causa: r);
  }
}
