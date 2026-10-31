/// Configuración PÚBLICA de las notificaciones push: solo la URL del Worker de
/// notificaciones (`cloudflare/push-notifications`). No hay ninguna credencial en
/// la app: la cuenta de servicio de FCM vive únicamente como secreto del Worker.
///
/// Se inyecta al compilar igual que la de ImageKit (`--dart-define` o
/// `--dart-define-from-file=env.json`):
///
/// ```
/// flutter run --dart-define=PUSH_NOTIFICATIONS_ENDPOINT=https://push-notifications.TU-SUBDOMINIO.workers.dev
/// ```
class PushConfig {
  /// URL HTTPS base del Worker (sin `/notify`).
  final String endpoint;

  const PushConfig({this.endpoint = ''});

  static const fromEnvironment = PushConfig(
    endpoint: String.fromEnvironment('PUSH_NOTIFICATIONS_ENDPOINT'),
  );

  /// Sin una URL HTTPS, la app no intenta avisar a nadie (y no falla).
  bool get configurado => endpoint.startsWith('https://');

  Uri get notifyUri => Uri.parse('${endpoint.replaceAll(RegExp(r'/+$'), '')}/notify');
}
