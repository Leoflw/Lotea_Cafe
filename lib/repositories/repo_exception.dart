import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Tipos de fallo que la interfaz distingue. Un fallo NUNCA se convierte en
/// "lista vacía": las pantallas muestran el estado que corresponda.
enum RepoErrorKind {
  sinConexion,
  sinPermisos,
  noEncontrado,
  duplicado,
  validacion,
  transicionInvalida,
  sinSesion,
  configuracionPendiente,
  credencialesInvalidas,
  otro,
}

class RepoException implements Exception {
  final RepoErrorKind tipo;
  final String mensaje;
  final Object? causa;

  const RepoException(this.tipo, this.mensaje, {this.causa});

  bool get esRecuperable =>
      tipo == RepoErrorKind.sinConexion || tipo == RepoErrorKind.otro;

  @override
  String toString() => 'RepoException($tipo): $mensaje';

  /// Traduce cualquier excepción de Firebase a un [RepoException] con un
  /// mensaje en español. Las excepciones propias se relanzan sin cambios.
  static RepoException desde(Object error) {
    if (error is RepoException) return error;
    if (error is FirebaseAuthException) return _desdeAuth(error);
    if (error is FirebaseException) return _desdeFirebase(error);
    return RepoException(RepoErrorKind.otro, 'Ocurrió un error inesperado. Inténtalo de nuevo.', causa: error);
  }

  static RepoException _desdeAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return RepoException(RepoErrorKind.duplicado, 'Ese correo ya está registrado. Inicia sesión o recupera tu contraseña.', causa: e);
      case 'invalid-email':
        return RepoException(RepoErrorKind.validacion, 'El correo electrónico no es válido.', causa: e);
      case 'weak-password':
        return RepoException(RepoErrorKind.validacion, 'La contraseña es demasiado débil. Usa al menos 8 caracteres con letras y números.', causa: e);
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return RepoException(RepoErrorKind.credencialesInvalidas, 'Correo o contraseña incorrectos.', causa: e);
      case 'user-disabled':
        return RepoException(RepoErrorKind.sinPermisos, 'Esta cuenta está deshabilitada.', causa: e);
      case 'too-many-requests':
        return RepoException(RepoErrorKind.otro, 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.', causa: e);
      case 'network-request-failed':
        return RepoException(RepoErrorKind.sinConexion, 'Sin conexión. Revisa tu internet e inténtalo de nuevo.', causa: e);
      case 'operation-not-allowed':
        return RepoException(RepoErrorKind.configuracionPendiente, 'El acceso con correo y contraseña no está activado en Firebase Authentication. Revisa FIREBASE_SETUP.md (paso 7).', causa: e);
      case 'requires-recent-login':
        return RepoException(RepoErrorKind.sinSesion, 'Por seguridad, vuelve a iniciar sesión.', causa: e);
      default:
        return RepoException(RepoErrorKind.otro, 'No se pudo completar la autenticación (${e.code}).', causa: e);
    }
  }

  static RepoException _desdeFirebase(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
      case 'unauthorized':
        return RepoException(RepoErrorKind.sinPermisos, 'No tienes permiso para realizar esta acción.', causa: e);
      case 'unauthenticated':
        return RepoException(RepoErrorKind.sinSesion, 'Tu sesión expiró. Inicia sesión de nuevo.', causa: e);
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return RepoException(RepoErrorKind.sinConexion, 'Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.', causa: e);
      case 'not-found':
      case 'object-not-found':
        return RepoException(RepoErrorKind.noEncontrado, 'No se encontró la información solicitada.', causa: e);
      case 'already-exists':
        return RepoException(RepoErrorKind.duplicado, 'Esa información ya existe.', causa: e);
      case 'failed-precondition':
        final msg = e.message ?? '';
        if (msg.contains('index')) {
          return RepoException(RepoErrorKind.configuracionPendiente, 'Falta un índice de Firestore para esta consulta. Despliega firestore.indexes.json (FIREBASE_SETUP.md, paso 10).', causa: e);
        }
        return RepoException(RepoErrorKind.otro, 'La operación no se pudo completar en el estado actual.', causa: e);
      case 'retry-limit-exceeded':
      case 'canceled':
        return RepoException(RepoErrorKind.otro, 'La operación se interrumpió. Inténtalo de nuevo.', causa: e);
      default:
        return RepoException(RepoErrorKind.otro, 'Error del servidor (${e.code}).', causa: e);
    }
  }
}

/// Ejecuta [accion] y traduce cualquier excepción de Firebase.
Future<T> guardar<T>(Future<T> Function() accion) async {
  try {
    return await accion();
  } on RepoException {
    rethrow;
  } on FirebaseException catch (e) {
    throw RepoException.desde(e);
  }
}

/// Envuelve un stream traduciendo sus errores (no los traga).
Stream<T> traducirErrores<T>(Stream<T> origen) {
  return origen.handleError((Object e, StackTrace s) {
    throw RepoException.desde(e);
  });
}
