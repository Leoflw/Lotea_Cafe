import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_diag.dart';

/// Dónde se guarda el booleano de «Mantener sesión iniciada» (en el teléfono).
///
/// Es una preferencia, no una credencial: aquí NUNCA se guardan contraseñas, correos,
/// UID ni tokens de autenticación. La sesión en sí la sigue guardando Firebase
/// Authentication de forma nativa.
abstract class AlmacenPreferenciaSesion {
  /// `null` si nunca se ha guardado.
  Future<bool?> leer();
  Future<void> guardar(bool mantener);
}

/// Implementación real con `shared_preferences`.
class AlmacenPreferenciaSesionLocal implements AlmacenPreferenciaSesion {
  static const clave = 'mantener_sesion';

  @override
  Future<bool?> leer() async => (await SharedPreferences.getInstance()).getBool(clave);

  @override
  Future<void> guardar(bool mantener) async {
    await (await SharedPreferences.getInstance()).setBool(clave, mantener);
  }
}

/// «Mantener sesión iniciada»: activada por defecto y **por dispositivo** (no por cuenta).
///
/// Con la opción desactivada la sesión actual sigue funcionando; al cerrar y volver a
/// abrir la app, `SessionProvider` cierra la sesión que Firebase restaura y aparece el
/// inicio de sesión.
class PreferenciaSesion extends ChangeNotifier {
  final AlmacenPreferenciaSesion? _almacen;
  bool _mantener;

  PreferenciaSesion._(this._almacen, this._mantener);

  /// Sin almacenamiento (pruebas y valor por defecto cuando no se inyecta otra cosa).
  factory PreferenciaSesion.enMemoria({bool mantener = true}) => PreferenciaSesion._(null, mantener);

  /// Lee el valor guardado. Sin valor, o si la lectura falla o tarda, se mantiene la
  /// sesión (el valor por defecto): un fallo del almacenamiento nunca cierra una sesión.
  static Future<PreferenciaSesion> cargar(AlmacenPreferenciaSesion almacen) async {
    var valor = true;
    try {
      final leido = await almacen.leer().timeout(const Duration(seconds: 2));
      valor = leido ?? true;
      AuthDiag.log('mantener_sesion almacenamiento: guardado=${leido ?? 'sin_valor(se_usa_true_por_defecto)'}');
    } catch (e) {
      // se queda el valor por defecto
      AuthDiag.log('mantener_sesion almacenamiento: lectura FALLÓ tipo=${AuthDiag.tipo(e)} (se_usa_true_por_defecto)');
    }
    return PreferenciaSesion._(almacen, valor);
  }

  bool get mantener => _mantener;

  /// Cambia y guarda la preferencia. Devuelve `false` (y deja el valor anterior) si no
  /// se pudo guardar.
  Future<bool> cambiar(bool nuevo) async {
    if (nuevo == _mantener) return true;
    final anterior = _mantener;
    _mantener = nuevo;
    notifyListeners();
    try {
      await _almacen?.guardar(nuevo);
      AuthDiag.log('mantener_sesion cambiada por la persona: $anterior -> $nuevo (guardada)');
      return true;
    } catch (e) {
      AuthDiag.log('mantener_sesion cambio NO guardado tipo=${AuthDiag.tipo(e)} (vuelve a $anterior)');
      _mantener = anterior;
      notifyListeners();
      return false;
    }
  }
}
