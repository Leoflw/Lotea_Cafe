/// Configuración PÚBLICA de ImageKit. Aquí solo van valores que pueden viajar
/// dentro de la app: la URL del Worker de autorización y la *public key* de
/// ImageKit. La *private key* NO existe en este proyecto: vive únicamente como
/// secreto del Cloudflare Worker (ver IMAGEKIT_SETUP.md).
///
/// Los valores se inyectan al compilar con `--dart-define` (o
/// `--dart-define-from-file=env.json`), así no hay que editar código ni
/// versionar claves:
///
/// ```
/// flutter run \
///   --dart-define=IMAGEKIT_AUTH_ENDPOINT=https://imagekit-upload-auth.TU-SUBDOMINIO.workers.dev \
///   --dart-define=IMAGEKIT_PUBLIC_KEY=public_xxxxxxxxxxxxxxxx= \
///   --dart-define=IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/TU_ID
/// ```
class ImageKitConfig {
  /// URL HTTPS del Worker que entrega la autorización de subida.
  final String authEndpoint;

  /// Public key de ImageKit (Developer options → API keys). Es pública.
  final String publicKey;

  /// URL endpoint de ImageKit (opcional). Solo sirve para reconocer URLs de
  /// dominios propios al optimizar la visualización.
  final String urlEndpoint;

  const ImageKitConfig({
    required this.authEndpoint,
    required this.publicKey,
    this.urlEndpoint = '',
  });

  static const fromEnvironment = ImageKitConfig(
    authEndpoint: String.fromEnvironment('IMAGEKIT_AUTH_ENDPOINT'),
    publicKey: String.fromEnvironment('IMAGEKIT_PUBLIC_KEY'),
    urlEndpoint: String.fromEnvironment('IMAGEKIT_URL_ENDPOINT'),
  );

  /// Valor por defecto del URL endpoint (vacío si no se definió).
  static const urlEndpointPorDefecto = String.fromEnvironment('IMAGEKIT_URL_ENDPOINT');

  /// API de subida de ImageKit (multipart/form-data sobre HTTPS).
  static const uploadEndpoint = 'https://upload.imagekit.io/api/v1/files/upload';

  /// Con el endpoint o la public key vacíos, o con un endpoint que no sea
  /// HTTPS, la app no intenta subir nada y lo explica al usuario.
  bool get configurado => authEndpoint.startsWith('https://') && publicKey.isNotEmpty;
}
