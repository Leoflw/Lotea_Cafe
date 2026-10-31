import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/repo_exception.dart';
import '../repositories/user_repository.dart';

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
  })  : _auth = auth,
        _users = users,
        _antesDeCerrarSesion = antesDeCerrarSesion {
    _authSub = _auth.authStateChanges.listen(_alCambiarAuth, onError: (Object e) {
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
    _firebaseUser = user;
    _userSub?.cancel();
    _userSub = null;
    _error = null;
    if (user == null) {
      _usuario = null;
      _pendiente = null;
      _status = SessionStatus.sinSesion;
      notifyListeners();
      return;
    }
    _status = SessionStatus.cargandoPerfil;
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

  /// Reintenta cargar el perfil tras un error recuperable.
  void reintentarPerfil() {
    final u = _firebaseUser;
    if (u == null) return;
    _status = SessionStatus.cargandoPerfil;
    _error = null;
    notifyListeners();
    _escucharPerfil(u.uid);
  }

  Future<void> iniciarSesion({required String email, required String password}) async {
    await _auth.iniciarSesion(email: email, password: password);
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
    await _auth.cerrarSesion();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
