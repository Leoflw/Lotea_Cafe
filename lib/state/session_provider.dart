import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/repo_exception.dart';
import '../repositories/user_repository.dart';
import '../services/auth_diag.dart';
import '../services/session_preference.dart';

enum SessionStatus {
  /// Esperando a que Firebase restaure (o descarte) la sesión guardada.
  iniciando,
  sinSesion,
  cargandoPerfil,

  /// Hay cuenta en Authentication pero no existe su documento `users/{uid}`
  /// (p. ej. falló la escritura justo después del registro).
  perfilFaltante,
  errorPerfil,
  listo,
}

class _RegistroPendiente {
  final String nombre;
  final UserRole rol;
  final String? ciudad;
  final TipoComprador? tipoComprador;
  const _RegistroPendiente(this.nombre, this.rol, this.ciudad, this.tipoComprador);
}

/// Sesión de la app. La fuente de verdad es Firebase Authentication (quién
/// es) y `users/{uid}` (su perfil y rol): aquí solo se refleja ese estado.
class SessionProvider extends ChangeNotifier {
  final AuthRepository _auth;
  final UserRepository _users;

  /// Se ejecuta ANTES de cerrar la sesión (con el UID que sale), mientras las reglas
  /// de Firestore aún permiten a esa cuenta borrar su dispositivo de notificaciones.
  /// Un fallo o una demora aquí nunca impide cerrar sesión.
  final Future<void> Function(String uid)? _antesDeCerrarSesion;

  /// «Mantener sesión iniciada» (por dispositivo). Sin preferencia se comporta como
  /// siempre: la sesión que Firebase restaura se conserva.
  final PreferenciaSesion? _preferencia;

  /// Igual que [_antesDeCerrarSesion], pero para una sesión RESTAURADA al abrir la app
  /// (arranque en frío) que se cierra porque la preferencia está desactivada. Un fallo o
  /// una demora aquí nunca impide cerrar la sesión.
  final Future<void> Function(String uid)? _antesDeCerrarSesionRestaurada;

  /// Solo el PRIMER evento de autenticación del proceso corresponde a una sesión
  /// restaurada; cualquier inicio de sesión posterior es una acción de la persona.
  bool _primerEventoDeAutenticacion = true;

  /// Usuario cuya sesión restaurada se está cerrando (o falló al cerrarse).
  User? _cierreRestauradoPendiente;
  bool _cerrado = false;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;

  SessionStatus _status = SessionStatus.iniciando;
  AppUser? _usuario;
  User? _firebaseUser;
  RepoException? _error;
  bool _registrando = false;
  _RegistroPendiente? _pendiente;

  SessionProvider({
    required AuthRepository auth,
    required UserRepository users,
    Future<void> Function(String uid)? antesDeCerrarSesion,
    PreferenciaSesion? preferencia,
    Future<void> Function(String uid)? antesDeCerrarSesionRestaurada,
  })  : _auth = auth,
        _users = users,
        _antesDeCerrarSesion = antesDeCerrarSesion,
        _preferencia = preferencia,
        _antesDeCerrarSesionRestaurada = antesDeCerrarSesionRestaurada {
    AuthDiag.log('SessionProvider creado: currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)} '
        'mantener_sesion=${AuthDiag.booleano(_preferencia?.mantener)} estado_inicial=${_status.name}');
    _authSub = _auth.authStateChanges.listen(_alCambiarAuth, onError: (Object e) {
      AuthDiag.log('authStateChanges ERROR tipo=${AuthDiag.tipo(e)} estado_anterior=${_status.name} estado_nuevo=errorPerfil');
      _error = RepoException.desde(e);
      _status = SessionStatus.errorPerfil;
      notifyListeners();
    });
  }

  SessionStatus get status => _status;
  AppUser? get usuario => _usuario;
  RepoException? get error => _error;
  bool get autenticado => _status == SessionStatus.listo && _usuario != null;
  bool get esVendedor => _usuario?.rol == UserRole.vendedor;
  String? get uid => _firebaseUser?.uid;
  String? get correo => _firebaseUser?.email;
  bool get correoVerificado => _firebaseUser?.emailVerified ?? true;

  void _alCambiarAuth(User? user) {
    // Sesión restaurada con «Mantener sesión iniciada» desactivada: se cierra SIN pasar por
    // `cargandoPerfil` ni `listo`. El estado se queda en `iniciando` (el splash), así la
    // pantalla principal nunca se construye y el puente de notificaciones nunca registra
    // este dispositivo para esa cuenta.
    final esPrimero = _primerEventoDeAutenticacion;
    _primerEventoDeAutenticacion = false;
    final preferencia = _preferencia;
    final estadoAnterior = _status;
    AuthDiag.log('authStateChanges evento: primero=$esPrimero user=${user == null ? 'null' : 'no_null'} '
        'currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)} '
        'comparacion=${AuthDiag.comparar(user, () => _auth.usuarioActual)} '
        'mantener_sesion=${AuthDiag.booleano(preferencia?.mantener)} '
        'estado_anterior=${estadoAnterior.name} signOuts_de_la_app=${AuthDiag.signOutsDeLaApp}');
    if (esPrimero && user != null && preferencia != null && !preferencia.mantener) {
      AuthDiag.log('decisión: CERRAR sesión restaurada automáticamente, '
          'razón=primer_evento_con_usuario_y_mantener_sesion=false');
      unawaited(_cerrarSesionRestaurada(user));
      return;
    }
    if (esPrimero && user != null) {
      AuthDiag.log('decisión: CONSERVAR sesión restaurada, '
          'razón=${preferencia == null ? 'sin_preferencia_inyectada' : 'mantener_sesion=true'}');
    }
    _cierreRestauradoPendiente = null;
    _firebaseUser = user;
    _userSub?.cancel();
    _userSub = null;
    _error = null;
    if (user == null) {
      _usuario = null;
      _pendiente = null;
      _status = SessionStatus.sinSesion;
      AuthDiag.log('estado: ${estadoAnterior.name} -> sinSesion (evento user=null)');
      notifyListeners();
      return;
    }
    _status = SessionStatus.cargandoPerfil;
    AuthDiag.log('estado: ${estadoAnterior.name} -> cargandoPerfil (evento con usuario)');
    notifyListeners();
    _escucharPerfil(user.uid);
  }

  void _escucharPerfil(String uid) {
    _userSub?.cancel();
    _userSub = _users.observar(uid).listen((perfil) {
      if (perfil == null) {
        _usuario = null;
        // Durante el registro el documento se crea unos instantes después
        // que la cuenta: no se muestra "perfil faltante" todavía.
        if (!_registrando) {
          _status = SessionStatus.perfilFaltante;
          notifyListeners();
        }
        return;
      }
      _usuario = perfil;
      _error = null;
      _status = SessionStatus.listo;
      notifyListeners();
    }, onError: (Object e) {
      _error = RepoException.desde(e);
      _status = SessionStatus.errorPerfil;
      notifyListeners();
    });
  }

  Future<void> _cerrarSesionRestaurada(User user) async {
    _cierreRestauradoPendiente = user;
    final gancho = _antesDeCerrarSesionRestaurada;
    if (gancho != null) {
      try {
        await gancho(user.uid).timeout(const Duration(seconds: 5));
      } catch (e) {
        // Las notificaciones nunca bloquean el cierre de sesión.
        AuthDiag.log('cierre AUTOMÁTICO: el gancho de dispositivo falló tipo=${AuthDiag.tipo(e)} (no bloquea el cierre)');
      }
    }
    try {
      AuthDiag.log('signOut AUTOMÁTICO: antes (currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)})');
      await _auth.cerrarSesion();
      AuthDiag.log('signOut AUTOMÁTICO: después, sin excepción (currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)})');
      // El siguiente evento (usuario nulo) lleva a `sinSesion` y al inicio de sesión.
    } catch (e) {
      AuthDiag.log('signOut AUTOMÁTICO: FALLÓ tipo=${AuthDiag.tipo(e)}');
      if (_cerrado) return;
      // No se pudo cerrar: nunca se entra a la app con una sesión que debía cerrarse.
      _firebaseUser = user;
      _error = const RepoException(RepoErrorKind.otro, 'No se pudo cerrar la sesión guardada. Inténtalo de nuevo.');
      _status = SessionStatus.errorPerfil;
      notifyListeners();
    }
  }

  /// Reintenta cargar el perfil tras un error recuperable. Si el error fue al cerrar una
  /// sesión restaurada, reintenta el cierre (no abre la app).
  void reintentarPerfil() {
    final pendiente = _cierreRestauradoPendiente;
    if (pendiente != null) {
      _error = null;
      _status = SessionStatus.iniciando;
      notifyListeners();
      unawaited(_cerrarSesionRestaurada(pendiente));
      return;
    }
    final u = _firebaseUser;
    if (u == null) return;
    _status = SessionStatus.cargandoPerfil;
    _error = null;
    notifyListeners();
    _escucharPerfil(u.uid);
  }

  Future<void> iniciarSesion({required String email, required String password}) async {
    await _auth.iniciarSesion(email: email, password: password);
    AuthDiag.log('inicio de sesión normal completado: currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)}');
    // El estado lo actualiza el listener de authStateChanges.
  }

  /// Registro: cuenta en Authentication → documento en Firestore. Si la
  /// cuenta se crea pero el documento falla, la sesión queda abierta y se
  /// lanza el error: la pantalla ofrece reintentar con [reintentarCreacionDePerfil]
  /// SIN volver a crear la cuenta (evita duplicados).
  Future<void> registrar({
    required String email,
    required String password,
    required String nombre,
    required UserRole rol,
    String? ciudad,
    TipoComprador? tipoComprador,
  }) async {
    _registrando = true;
    _pendiente = _RegistroPendiente(nombre.trim(), rol, ciudad, tipoComprador);
    var documentoCreado = false;
    try {
      final user = await _auth.registrar(email: email, password: password);
      _firebaseUser = user;
      await _crearDocumento(user);
      documentoCreado = true;
    } finally {
      _registrando = false;
      // Cuenta creada pero documento no: queda en "perfil faltante" y se
      // puede reintentar sin crear otra cuenta.
      if (!documentoCreado && _firebaseUser != null) {
        _status = SessionStatus.perfilFaltante;
        notifyListeners();
      }
    }
  }

  Future<void> _crearDocumento(User user) async {
    final p = _pendiente;
    if (p == null) {
      throw const RepoException(RepoErrorKind.validacion, 'Faltan los datos del perfil.');
    }
    await _users.crear(AppUser(
      uid: user.uid,
      email: (user.email ?? '').toLowerCase(),
      nombre: p.nombre,
      rol: p.rol,
      ciudad: (p.ciudad ?? '').trim().isEmpty ? null : p.ciudad!.trim(),
      tipoComprador: p.tipoComprador,
    ));
  }

  /// Crea el documento de perfil de una cuenta que ya existe en
  /// Authentication (nombre y rol los elige la persona en la pantalla de
  /// "completar perfil").
  Future<void> completarPerfilFaltante({required String nombre, required UserRole rol}) async {
    final user = _firebaseUser;
    if (user == null) throw const RepoException(RepoErrorKind.sinSesion, 'No hay una sesión activa.');
    _pendiente = _RegistroPendiente(nombre.trim(), rol, null, null);
    _registrando = true;
    try {
      await _crearDocumento(user);
    } finally {
      _registrando = false;
    }
  }

  Future<void> reintentarCreacionDePerfil() async {
    final user = _firebaseUser;
    if (user == null) throw const RepoException(RepoErrorKind.sinSesion, 'No hay una sesión activa.');
    _registrando = true;
    try {
      await _crearDocumento(user);
    } finally {
      _registrando = false;
    }
  }

  bool get hayRegistroPendiente => _pendiente != null;

  Future<void> actualizarUsuario(AppUser usuario) => _users.actualizar(usuario);

  Future<void> completarOnboarding() async {
    final u = _usuario;
    if (u == null) return;
    await _users.actualizar(u.copyWith(onboardingCompleto: true));
  }

  Future<void> recuperarPassword(String email) => _auth.enviarRecuperacion(email);
  Future<void> enviarVerificacionCorreo() => _auth.enviarVerificacion();

  Future<void> comprobarVerificacion() async {
    await _auth.correoVerificado();
    notifyListeners();
  }

  /// Cierra la sesión de Firebase. Los providers que dependen de la sesión
  /// cancelan sus suscripciones y vacían su estado al ver que cambia.
  Future<void> cerrarSesion() async {
    final uid = _firebaseUser?.uid;
    final antes = _antesDeCerrarSesion;
    if (uid != null && antes != null) {
      try {
        await antes(uid).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Las notificaciones nunca bloquean el cierre de sesión.
      }
    }
    try {
      AuthDiag.log('signOut MANUAL: antes (currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)})');
      await _auth.cerrarSesion();
      AuthDiag.log('signOut MANUAL: después, sin excepción (currentUser=${AuthDiag.actualNulo(() => _auth.usuarioActual)})');
    } catch (e) {
      AuthDiag.log('signOut MANUAL: FALLÓ tipo=${AuthDiag.tipo(e)}');
      rethrow;
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
