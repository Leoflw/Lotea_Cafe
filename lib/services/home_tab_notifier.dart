import 'package:flutter/foundation.dart';

/// Pestaña activa de [HomeShell]. Vive fuera del State del shell para que
/// cualquier pantalla (p. ej. el snackbar "Ver solicitudes") pueda cambiar
/// de pestaña sin duplicar navegación ni empujar rutas paralelas.
/// Comprador: 0 Descubrir · 1 Solicitudes · 2 Guardados · 3 Cuenta.
/// Vendedor:  0 Mi catálogo · 1 Solicitudes · 2 Cuenta.
class HomeTabNotifier extends ChangeNotifier {
  int _indice = 0;
  int get indice => _indice;

  void ir(int nuevo) {
    if (nuevo == _indice) return;
    _indice = nuevo;
    notifyListeners();
  }

  void reiniciar() {
    if (_indice == 0) return;
    _indice = 0;
    notifyListeners();
  }
}
