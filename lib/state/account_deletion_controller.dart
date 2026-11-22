import 'package:flutter/foundation.dart';
import '../repositories/account_deletion_client.dart';
import '../repositories/auth_repository.dart';
import '../repositories/repo_exception.dart';

/// Orquesta «solicitar / cancelar la eliminación de la cuenta»: reautentica con la contraseña de
/// Firebase Authentication, toma un ID token recién emitido y se lo entrega al Worker.
///
/// - La contraseña solo pasa como argumento: no se guarda en ningún campo, ni se registra.
/// - Solo hay UNA operación a la vez: una segunda llamada mientras hay otra en curso se rechaza
///   (sin tocar Authentication ni el Worker).
/// - Devuelve el estado que CONFIRMÓ el Worker; ante cualquier fallo lanza [RepoException] (nunca éxito falso).
class AccountDeletionController extends ChangeNotifier {
  final AuthRepository _auth;
  final AccountDeletionClient _client;
  bool _ocupado = false;

  AccountDeletionController({required AuthRepository auth, required AccountDeletionClient client})
      : _auth = auth,
        _client = client;

  bool get ocupado => _ocupado;

  Future<EstadoEliminacionCuenta> solicitar(String password) => _ejecutar(password, _client.solicitar);
  Future<EstadoEliminacionCuenta> cancelar(String password) => _ejecutar(password, _client.cancelar);

  Future<EstadoEliminacionCuenta> _ejecutar(String password, Future<EstadoEliminacionCuenta> Function(String token) accion) async {
    if (_ocupado) throw const RepoException(RepoErrorKind.otro, 'Ya hay una operación en curso. Espera un momento.');
    _ocupado = true;
    notifyListeners();
    try {
      final token = await _auth.reautenticar(password);
      return await accion(token);
    } finally {
      _ocupado = false;
      notifyListeners();
    }
  }
}
