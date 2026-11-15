import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/imagekit_config.dart';
import 'image_repository.dart' show TokenProvider;

/// Cliente del Worker de limpieza de ImageKit. Solo le dice «procesa MI cola»
/// con el token de Firebase de la persona; NO envía ningún fileId (el Worker
/// los lee de la cola y los valida) y NUNCA habla con ImageKit.
///
/// Es un aviso de mejor esfuerzo: no lanza nunca y no devuelve nada, porque la
/// limpieza es secundaria al guardado. Si falla o no hay endpoint configurado,
/// las solicitudes siguen en la cola y el cron del Worker las procesa.
class ImageCleanupClient {
  final http.Client _client;
  final TokenProvider? _tokenProvider;
  final ImageKitConfig _config;
  final Duration _timeout;

  ImageCleanupClient({
    http.Client? client,
    TokenProvider? tokenProvider,
    ImageKitConfig config = ImageKitConfig.fromEnvironment,
    Duration timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider,
        _config = config,
        _timeout = timeout;

  bool get configurado => _config.cleanupEndpoint.startsWith('https://');

  Future<String?> _token() {
    final p = _tokenProvider;
    if (p != null) return p();
    return FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);
  }

  Future<void> procesarCola() async {
    if (!configurado) return;
    try {
      final token = await _token();
      if (token == null || token.isEmpty) return;
      await _client.post(Uri.parse(_config.cleanupEndpoint), headers: {'Authorization': 'Bearer $token'}).timeout(_timeout);
    } catch (_) {
      // Mejor esfuerzo: la solicitud sigue en la cola.
    }
  }
}
