import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> cerrarSesion() => _auth.signOut();

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
