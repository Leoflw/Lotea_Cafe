import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/imagekit_config.dart';
import 'repo_exception.dart';

/// Lo que el Worker confirma tras solicitar o cancelar la eliminación de la cuenta.
class EstadoEliminacionCuenta {
  /// `eliminacionPendiente` (tras solicitar) o `activa` (tras cancelar).
  final String estado;
  final DateTime? solicitadaAt;
  final DateTime? programadaAt;
  final int? retencionDias;

  /// La llamada repetía una solicitud/cancelación ya registrada: no cambió nada.
  final bool idempotente;

  const EstadoEliminacionCuenta({required this.estado, this.solicitadaAt, this.programadaAt, this.retencionDias, this.idempotente = false});

  bool get pendiente => estado == 'eliminacionPendiente';

  factory EstadoEliminacionCuenta.desdeJson(Map<String, dynamic> m) => EstadoEliminacionCuenta(
        estado: m['estado'] as String,
        solicitadaAt: _fecha(m['solicitadaAt']),
        programadaAt: _fecha(m['programadaAt']),
        retencionDias: m['retencionDias'] is int ? m['retencionDias'] as int : null,
        idempotente: m['idempotente'] == true,
      );

  static DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Cliente del módulo de ciclo de vida de cuentas del Worker `imagekit-cleanup`
/// (`POST /account-deletion/request` y `/cancel`). Usa el ID token que se le entrega (recién
/// obtenido tras reautenticar); no envía ningún dato de la persona en el cuerpo (el Worker toma el
/// UID del token y calcula las fechas con su propio reloj). No guarda ni imprime el token.
///
/// Nunca devuelve «éxito» sin la confirmación del Worker: cualquier otro resultado lanza [RepoException].
class AccountDeletionClient {
  final http.Client _client;
  final ImageKitConfig _config;
  final Duration _timeout;

  AccountDeletionClient({
    http.Client? client,
    ImageKitConfig config = ImageKitConfig.fromEnvironment,
    Duration timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _config = config,
        _timeout = timeout;

  bool get configurado => _config.cleanupEndpoint.startsWith('https://');

  Future<EstadoEliminacionCuenta> solicitar(String idToken) => _post('/account-deletion/request', idToken);
  Future<EstadoEliminacionCuenta> cancelar(String idToken) => _post('/account-deletion/cancel', idToken);

  Future<EstadoEliminacionCuenta> _post(String ruta, String idToken) async {
    if (!configurado) {
      throw const RepoException(RepoErrorKind.configuracionPendiente, 'La eliminación de cuenta todavía no está disponible en esta versión de la app.');
    }
    final http.Response resp;
    try {
      resp = await _client
          .post(Uri.parse(_config.cleanupEndpoint).resolve(ruta), headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'}, body: '{}')
          .timeout(_timeout);
    } on TimeoutException {
      throw const RepoException(RepoErrorKind.sinConexion, 'El servidor tardó demasiado en responder. Revisa tu conexión y vuelve a intentarlo.');
    } catch (_) {
      throw const RepoException(RepoErrorKind.sinConexion, 'No hay conexión con el servidor. Revisa tu internet y vuelve a intentarlo.');
    }
    Map<String, dynamic>? cuerpo;
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map<String, dynamic>) cuerpo = d;
    } catch (_) {
      cuerpo = null;
    }
    if (resp.statusCode == 200 && cuerpo != null && cuerpo['estado'] is String) {
      return EstadoEliminacionCuenta.desdeJson(cuerpo);
    }
    throw _error(resp.statusCode, cuerpo);
  }

  static RepoException _error(int estado, Map<String, dynamic>? cuerpo) {
    final codigo = cuerpo?['codigo'];
    final mensaje = cuerpo?['error'];
    final delServidor = mensaje is String && mensaje.isNotEmpty ? mensaje : null;
    switch (estado) {
      case 400:
        return const RepoException(RepoErrorKind.validacion, 'No se pudo procesar la solicitud. Actualiza la app e inténtalo de nuevo.');
      case 401:
        // Reautenticación o sesión inválida: se pide volver a escribir la contraseña / iniciar sesión.
        return RepoException(RepoErrorKind.sinSesion, codigo == 'reautenticacion' ? 'Por seguridad, confirma de nuevo tu contraseña e inténtalo otra vez.' : 'Tu sesión no es válida. Inicia sesión de nuevo.');
      case 403:
        return const RepoException(RepoErrorKind.sinPermisos, 'Esta cuenta no puede realizar la operación.');
      case 409:
        return RepoException(RepoErrorKind.transicionInvalida, delServidor ?? 'No se puede realizar la operación en el estado actual de tu cuenta.');
      case 429:
        return const RepoException(RepoErrorKind.otro, 'Demasiados intentos seguidos. Espera unos minutos e inténtalo de nuevo.');
      default:
        return const RepoException(RepoErrorKind.otro, 'No pudimos completar la operación ahora. Inténtalo de nuevo en unos minutos.');
    }
  }
}
