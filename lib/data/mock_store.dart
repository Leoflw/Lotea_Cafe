import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/coffee_profile.dart';
import '../models/match_model.dart';
import '../models/chat_message.dart';

class AuthException implements Exception {
  final String mensaje;
  AuthException(this.mensaje);
}

/// Reemplaza a Firebase para esta build de pruebas: todo vive en RAM.
/// Se reinicia cada vez que se cierra o se mata la app — ideal para
/// probar únicamente la funcionalidad de las pantallas, sin persistencia.
class MockStore extends ChangeNotifier {
  final List<AppUser> _usuarios = [];
  final Map<String, String> _passwords = {}; // email -> password
  final List<CoffeeProfile> _perfiles = [];
  final List<_Like> _likes = [];
  final List<MatchModel> _matches = [];
  final Map<String, List<ChatMessage>> _mensajes = {};

  int _contador = 0;
  String _nuevoId(String prefijo) => '$prefijo${_contador++}';

  MockStore() {
    _sembrarDatosDemo();
  }

  // ---------------------------------------------------------------------
  // AUTENTICACIÓN (simulada, en memoria)
  // ---------------------------------------------------------------------

  AppUser registrar({
    required String email,
    required String password,
    required String nombre,
    required UserRole rol,
  }) {
    final emailNormalizado = email.trim().toLowerCase();
    if (_passwords.containsKey(emailNormalizado)) {
      throw AuthException('Ese correo ya está registrado en esta sesión de prueba.');
    }
    final usuario = AppUser(
      uid: _nuevoId('user_'),
      email: emailNormalizado,
      nombre: nombre.trim(),
      rol: rol,
    );
    _usuarios.add(usuario);
    _passwords[emailNormalizado] = password;
    notifyListeners();
    return usuario;
  }

  AppUser iniciarSesion({required String email, required String password}) {
    final emailNormalizado = email.trim().toLowerCase();
    final claveGuardada = _passwords[emailNormalizado];
    if (claveGuardada == null || claveGuardada != password) {
      throw AuthException('Correo o contraseña incorrectos.');
    }
    return _usuarios.firstWhere((u) => u.email == emailNormalizado);
  }

  // ---------------------------------------------------------------------
  // PERFILES DE CAFÉ
  // ---------------------------------------------------------------------

  void guardarPerfil(CoffeeProfile perfil) {
    _perfiles.removeWhere((p) => p.id == perfil.id);
    _perfiles.add(perfil);
    notifyListeners();
  }

  CoffeeProfile? obtenerPerfilDeVendedor(String vendedorId) {
    for (final p in _perfiles) {
      if (p.vendedorId == vendedorId) return p;
    }
    return null;
  }

  List<CoffeeProfile> obtenerPerfilesParaDescubrir({
    required String compradorId,
    List<String>? variedades,
    double? precioMax,
    String? proceso,
  }) {
    final yaCalificados = _likes
        .where((l) => l.compradorId == compradorId)
        .map((l) => l.perfilId)
        .toSet();

    return _perfiles.where((p) {
      if (!p.publicado) return false;
      if (p.vendedorId == compradorId) return false;
      if (yaCalificados.contains(p.id)) return false;
      if (proceso != null && proceso.isNotEmpty && p.proceso != proceso) return false;
      if (variedades != null &&
          variedades.isNotEmpty &&
          !p.variedades.any(variedades.contains)) {
        return false;
      }
      if (precioMax != null && p.precioPorKg > precioMax) return false;
      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------
  // SWIPE / MATCH
  // ---------------------------------------------------------------------

  MatchModel? registrarSwipe({
    required String compradorId,
    required CoffeeProfile perfil,
    required bool esLike,
  }) {
    _likes.add(_Like(compradorId: compradorId, perfilId: perfil.id, esLike: esLike));

    if (!esLike) {
      notifyListeners();
      return null;
    }

    final match = MatchModel(
      id: _nuevoId('match_'),
      compradorId: compradorId,
      vendedorId: perfil.vendedorId,
      perfilId: perfil.id,
    );
    _matches.add(match);
    notifyListeners();
    return match;
  }

  List<MatchModel> matchesDelUsuario(String uid, {required bool esComprador}) {
    final lista = esComprador
        ? _matches.where((m) => m.compradorId == uid)
        : _matches.where((m) => m.vendedorId == uid);
    return lista.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  AppUser? usuarioPorId(String uid) {
    for (final u in _usuarios) {
      if (u.uid == uid) return u;
    }
    return null;
  }

  CoffeeProfile? perfilPorId(String perfilId) {
    for (final p in _perfiles) {
      if (p.id == perfilId) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // CHAT
  // ---------------------------------------------------------------------

  List<ChatMessage> mensajesDeChat(String chatId) => _mensajes[chatId] ?? [];

  void enviarMensaje(ChatMessage mensaje) {
    _mensajes.putIfAbsent(mensaje.chatId, () => []).add(mensaje);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // DATOS DE DEMO (para poder probar el swipe sin registrar vendedores)
  // ---------------------------------------------------------------------

  void _sembrarDatosDemo() {
    final demo = <Map<String, dynamic>>[
      {
        'nombre': 'Finca La Esperanza',
        'vendedor': 'Carlos Ramírez',
        'variedades': ['Arábica', 'Geisha'],
        'altitud': 1750.0,
        'proceso': 'Lavado',
        'precio': 12.5,
        'desc': 'Café de altura con notas florales y cítricas.',
        'cert': ['Orgánico'],
      },
      {
        'nombre': 'Finca El Mirador',
        'vendedor': 'Ana Gómez',
        'variedades': ['Bourbon', 'Caturra'],
        'altitud': 1600.0,
        'proceso': 'Honey',
        'precio': 9.8,
        'desc': 'Dulzor a panela y cuerpo cremoso, ideal para espresso.',
        'cert': ['Fair Trade'],
      },
      {
        'nombre': 'Finca Santa Rosa',
        'vendedor': 'Jorge Duarte',
        'variedades': ['Typica'],
        'altitud': 1400.0,
        'proceso': 'Natural',
        'precio': 8.2,
        'desc': 'Notas a frutos rojos, fermentación controlada.',
        'cert': [],
      },
      {
        'nombre': 'Finca Los Robles',
        'vendedor': 'María Torres',
        'variedades': ['Geisha', 'Caturra'],
        'altitud': 1900.0,
        'proceso': 'Lavado',
        'precio': 18.0,
        'desc': 'Café de especialidad, puntaje de taza 88+.',
        'cert': ['Orgánico', 'Origen certificado'],
      },
      {
        'nombre': 'Finca El Paraíso',
        'vendedor': 'Luis Fernández',
        'variedades': ['Robusta'],
        'altitud': 900.0,
        'proceso': 'Natural',
        'precio': 5.5,
        'desc': 'Ideal para mezclas, cuerpo intenso y bajo costo.',
        'cert': [],
      },
    ];

    for (final d in demo) {
      final vendedorId = _nuevoId('demo_vendedor_');
      _usuarios.add(AppUser(
        uid: vendedorId,
        email: '${d['vendedor'].toString().split(' ').first.toLowerCase()}@demo.cafe',
        nombre: d['vendedor'] as String,
        rol: UserRole.vendedor,
      ));
      _perfiles.add(CoffeeProfile(
        id: _nuevoId('demo_perfil_'),
        vendedorId: vendedorId,
        nombreVendedor: d['vendedor'] as String,
        finca: d['nombre'] as String,
        variedades: List<String>.from(d['variedades'] as List),
        altitudMsnm: d['altitud'] as double,
        proceso: d['proceso'] as String,
        descripcion: d['desc'] as String,
        precioPorKg: d['precio'] as double,
        certificaciones: List<String>.from(d['cert'] as List),
        calificacionPromedio: 4.2 + (_contador % 8) / 10,
        publicado: true,
      ));
    }
  }
}

class _Like {
  final String compradorId;
  final String perfilId;
  final bool esLike;
  _Like({required this.compradorId, required this.perfilId, required this.esLike});
}
