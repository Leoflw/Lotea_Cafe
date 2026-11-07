import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';

void main() {
  test('permission-denied se distingue de sin conexión', () {
    final denegado = RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    final offline = RepoException.desde(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    expect(denegado.tipo, RepoErrorKind.sinPermisos);
    expect(offline.tipo, RepoErrorKind.sinConexion);
    expect(offline.esRecuperable, isTrue);
  });

  test('un índice faltante se reporta como configuración pendiente', () {
    final e = RepoException.desde(
      FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition', message: 'The query requires an index.'),
    );
    expect(e.tipo, RepoErrorKind.configuracionPendiente);
  });

  test('errores de autenticación tienen mensajes en español', () {
    final e = RepoException.desde(FirebaseAuthException(code: 'email-already-in-use'));
    expect(e.tipo, RepoErrorKind.duplicado);
    expect(e.mensaje, contains('registrado'));
    expect(RepoException.desde(FirebaseAuthException(code: 'wrong-password')).tipo, RepoErrorKind.credencialesInvalidas);
  });
}
