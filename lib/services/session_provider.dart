import 'package:flutter/foundation.dart';
import '../data/mock_store.dart';
import '../models/app_user.dart';

/// Mantiene en memoria al usuario "autenticado" actual. El registro/login
/// vive en [MockStore]; esta clase solo guarda la sesión activa mientras la
/// app está abierta.
class SessionProvider extends ChangeNotifier {
  final MockStore store;
  AppUser? _usuario;

  SessionProvider(this.store);

  AppUser? get usuario => _usuario;
  bool get autenticado => _usuario != null;
  bool get esVendedor => _usuario?.rol == UserRole.vendedor;

  AppUser registrar({
    required String email,
    required String password,
    required String nombre,
    required UserRole rol,
  }) {
    final u = store.registrar(email: email, password: password, nombre: nombre, rol: rol);
    _usuario = u;
    notifyListeners();
    return u;
  }

  AppUser iniciarSesion({required String email, required String password}) {
    final u = store.iniciarSesion(email: email, password: password);
    _usuario = u;
    notifyListeners();
    return u;
  }

  void actualizarUsuario(AppUser usuario) {
    store.actualizarUsuario(usuario);
    _usuario = usuario;
    notifyListeners();
  }

  void cerrarSesion() {
    _usuario = null;
    notifyListeners();
  }
}
