import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_diag.dart';
import 'repo_exception.dart';

/// Envuelve Firebase Authentication. Las contraseñas solo pasan por aquí
/// hacia Firebase: jamás se guardan en Firestore ni en memoria de la app.
class AuthRepository {
  final FirebaseAuth _auth;
  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get usuarioActual => _auth.currentUser;

  Future<User> registrar({required String email, required String password}) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      final user = cred.user;
      if (user == null) {
        throw const RepoException(RepoErrorKind.otro, 'No se pudo crear la cuenta. Inténtalo de nuevo.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw RepoException.desde(e);
    }
  }

  Future<User> iniciarSesion({required String email, required String password}) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      final user = cred.user;
      if (user == null) {
        throw const RepoException(RepoErrorKind.otro, 'No se pudo iniciar sesión. Inténtalo de nuevo.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw RepoException.desde(e);
    }
  }

  /// Reautentica a la persona con su contraseña de Firebase Authentication y devuelve un ID token
  /// RECIÉN emitido (`getIdToken(true)`, con `auth_time` actual) para las rutas del Worker que lo exigen.
  ///
  /// Usa `currentUser` y el correo que Authentication confirma. La contraseña solo viaja hacia Firebase:
  /// no se guarda, no se registra y no se devuelve. El token tampoco se imprime.
  Future<String> reautenticar(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw const RepoException(RepoErrorKind.sinSesion, 'Tu sesión terminó. Inicia sesión de nuevo.');
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw const RepoException(RepoErrorKind.validacion, 'No pudimos confirmar el correo de tu cuenta, así que no es posible verificar tu identidad.');
    }
    if (password.isEmpty) throw const RepoException(RepoErrorKind.validacion, 'Escribe tu contraseña para continuar.');
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: email, password: password));
      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const RepoException(RepoErrorKind.sinSesion, 'No pudimos confirmar tu sesión. Inténtalo de nuevo.');
      }
      return token;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          throw RepoException(RepoErrorKind.credencialesInvalidas, 'La contraseña no es correcta.', causa: e);
        case 'requires-recent-login':
        case 'user-token-expired':
        case 'user-not-found':
          throw RepoException(RepoErrorKind.sinSesion, 'Por seguridad, inicia sesión de nuevo e inténtalo otra vez.', causa: e);
        default:
          throw RepoException.desde(e);
      }
    }
  }

  Future<void> cerrarSesion() async {
    AuthDiag.signOutsDeLaApp++;
    AuthDiag.log('FirebaseAuth.signOut() INVOCADO por la app (llamada n.º ${AuthDiag.signOutsDeLaApp}) '
        'currentUser=${AuthDiag.actualNulo(() => _auth.currentUser)}');
    await _auth.signOut();
    AuthDiag.log('FirebaseAuth.signOut() TERMINÓ currentUser=${AuthDiag.actualNulo(() => _auth.currentUser)}');
  }

  Future<void> enviarRecuperacion(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Por privacidad no revelamos si el correo existe.
      if (e.code == 'user-not-found') return;
      throw RepoException.desde(e);
    }
  }

  Future<void> enviarVerificacion() async {
    final user = _auth.currentUser;
    if (user == null) throw const RepoException(RepoErrorKind.sinSesion, 'No hay una sesión activa.');
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw RepoException.desde(e);
    }
  }

  /// Recarga el usuario para saber si ya verificó su correo.
  Future<bool> correoVerificado() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
    } on FirebaseAuthException catch (e) {
      throw RepoException.desde(e);
    }
    return _auth.currentUser?.emailVerified ?? false;
  }
}
