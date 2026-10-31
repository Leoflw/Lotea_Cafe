import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

enum FirebaseInitStatus { listo, configuracionPendiente, fallo }

class FirebaseInitResult {
  final FirebaseInitStatus status;
  final String? detalle;
  const FirebaseInitResult(this.status, [this.detalle]);
}

/// Inicializa Firebase UNA sola vez antes de `runApp`.
///
/// Usa la configuración nativa que genera `flutterfire configure`
/// (google-services.json en Android). No existe `firebase_options.dart`
/// inventado: si el proyecto aún no está conectado, la inicialización falla
/// y la app muestra la pantalla de "configuración pendiente" en lugar de una
/// pantalla en blanco — y sin activar ningún modo demo.
class FirebaseBootstrap {
  static Future<FirebaseInitResult> inicializar() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return const FirebaseInitResult(FirebaseInitStatus.listo);
    } on FirebaseException catch (e) {
      return _clasificar(e.code, e.message);
    } catch (e) {
      // No se simula éxito: el error se muestra en pantalla (con su detalle).
      return FirebaseInitResult(FirebaseInitStatus.fallo, e.toString());
    }
  }

  static FirebaseInitResult _clasificar(String code, String? message) {
    final texto = '${code.toLowerCase()} ${(message ?? '').toLowerCase()}';
    final faltaConfig = texto.contains('not-initialized') ||
        texto.contains('google-services') ||
        texto.contains('api key') ||
        texto.contains('options') ||
        texto.contains('missing') ||
        texto.contains('no-app') ||
        texto.contains('core/not-initialized');
    return FirebaseInitResult(
      faltaConfig ? FirebaseInitStatus.configuracionPendiente : FirebaseInitStatus.fallo,
      message ?? code,
    );
  }
}
