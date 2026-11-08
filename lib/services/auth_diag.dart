import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// DIAGNÓSTICO TEMPORAL de la persistencia de sesión (prefijo `[AUTH_DIAG]`).
///
/// Solo escribe en el registro de depuración y solo en modo debug (`kDebugMode`): en
/// `profile` y `release` no imprime nada. No cambia ninguna decisión de la app.
///
/// PRIVACIDAD: este archivo nunca recibe ni imprime correo, contraseña, UID, tokens ni
/// datos del perfil. Los usuarios de Firebase solo se examinan para saber si son nulos o
/// si dos referencias son la misma cuenta, y de eso solo se imprime una etiqueta fija.
/// De una excepción solo se imprime su tipo (y el `code` de `FirebaseAuthException`,
/// que es un identificador fijo como `network-request-failed`), nunca su mensaje.
///
/// Para retirarlo: borrar este archivo y las líneas `AuthDiag.` de los archivos que lo usan.
class AuthDiag {
  AuthDiag._();

  static const String prefijo = '[AUTH_DIAG]';

  /// Milisegundos desde la primera llamada a [log] (la de `main() inicia`). Sirve para
  /// ordenar los mensajes y ver cuánto tarda cada paso.
  static final Stopwatch _reloj = Stopwatch()..start();

  /// Cuántas veces el código de la app llamó a `FirebaseAuth.signOut()` (lo incrementa
  /// `AuthRepository.cerrarSesion`). Un evento `user=null` con este contador en 0 no lo
  /// provocó la app: lo emitió el SDK de Firebase.
  static int signOutsDeLaApp = 0;

  /// Solo para pruebas: recibe cada línea en lugar de `debugPrint`.
  @visibleForTesting
  static void Function(String linea)? sumidero;

  static void log(String mensaje) {
    if (!kDebugMode) return;
    final linea = '$prefijo +${_reloj.elapsedMilliseconds}ms $mensaje';
    final destino = sumidero;
    if (destino != null) {
      destino(linea);
      return;
    }
    debugPrint(linea);
  }

  /// `null`, `no_null` o `no_disponible` (si leer el usuario actual lanzó una excepción,
  /// p. ej. Firebase aún sin inicializar).
  static String actualNulo(User? Function() leer) {
    try {
      return leer() == null ? 'null' : 'no_null';
    } catch (_) {
      return 'no_disponible';
    }
  }

  /// Estado de `FirebaseAuth.instance.currentUser` ahora mismo.
  static String actualDeFirebase() => actualNulo(() => FirebaseAuth.instance.currentUser);

  /// Relación entre el usuario que EMITIÓ `authStateChanges` y el `currentUser` en ese
  /// momento. Solo devuelve una etiqueta fija; el UID se compara pero no se imprime.
  static String comparar(User? emitido, User? Function() leerActual) {
    try {
      final actual = leerActual();
      if (emitido == null && actual == null) return 'ambos_null';
      if (emitido == null) return 'emitido_null_actual_presente';
      if (actual == null) return 'emitido_presente_actual_null';
      return emitido.uid == actual.uid ? 'mismo_usuario' : 'usuarios_distintos';
    } catch (_) {
      return 'actual_no_disponible';
    }
  }

  /// `true`, `false` o `sin_preferencia` (cuando no hay `PreferenciaSesion` inyectada).
  static String booleano(bool? valor) => valor == null ? 'sin_preferencia' : '$valor';

  /// Tipo de la excepción, sin su mensaje.
  static String tipo(Object error) {
    if (error is FirebaseAuthException) return '${error.runtimeType}(code=${error.code})';
    return error.runtimeType.toString();
  }
}
