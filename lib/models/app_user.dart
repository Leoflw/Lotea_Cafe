import '../data/codec.dart';

enum UserRole { comprador, vendedor }

extension UserRoleX on UserRole {
  String get label => this == UserRole.vendedor ? 'Vendedor' : 'Comprador';
}

/// Tipo de negocio del comprador.
enum TipoComprador { cafeteria, tostador, restaurante, distribuidor, independiente }

extension TipoCompradorX on TipoComprador {
  String get label {
    switch (this) {
      case TipoComprador.cafeteria:
        return 'Cafetería';
      case TipoComprador.tostador:
        return 'Tostador';
      case TipoComprador.restaurante:
        return 'Restaurante';
      case TipoComprador.distribuidor:
        return 'Distribuidor';
      case TipoComprador.independiente:
        return 'Comprador independiente';
    }
  }
}

/// Preferencias de compra: se usan para mostrar "Coincide con tus
/// preferencias" y ordenar por relevancia.
class BuyerPreferences {
  final List<String> variedades;
  final List<String> regiones;
  final List<String> procesos;
  final double? precioMaxCOP;
  final double? cantidadAproxKg;

  const BuyerPreferences({
    this.variedades = const [],
    this.regiones = const [],
    this.procesos = const [],
    this.precioMaxCOP,
    this.cantidadAproxKg,
  });

  BuyerPreferences copyWith({
    List<String>? variedades,
    List<String>? regiones,
    List<String>? procesos,
    double? precioMaxCOP,
    double? cantidadAproxKg,
  }) {
    return BuyerPreferences(
      variedades: variedades ?? this.variedades,
      regiones: regiones ?? this.regiones,
      procesos: procesos ?? this.procesos,
      precioMaxCOP: precioMaxCOP ?? this.precioMaxCOP,
      cantidadAproxKg: cantidadAproxKg ?? this.cantidadAproxKg,
    );
  }

  bool get estaVacia =>
      variedades.isEmpty && regiones.isEmpty && procesos.isEmpty && precioMaxCOP == null;

  Map<String, dynamic> toMap() => {
        'variedades': variedades,
        'regiones': regiones,
        'procesos': procesos,
        'precioMaxCOP': precioMaxCOP,
        'cantidadAproxKg': cantidadAproxKg,
      };

  factory BuyerPreferences.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BuyerPreferences();
    return BuyerPreferences(
      variedades: readStringList(m['variedades']),
      regiones: readStringList(m['regiones']),
      procesos: readStringList(m['procesos']),
      precioMaxCOP: readDouble(m['precioMaxCOP']),
      cantidadAproxKg: readDouble(m['cantidadAproxKg']),
    );
  }
}

/// Documento `users/{uid}`. Nunca contiene contraseñas. El rol se fija en el
/// registro y las reglas de Firestore impiden cambiarlo después.
class AppUser {
  final String uid;
  final String email;
  final String nombre;
  final UserRole rol;
  final String? fotoPath;
  final String? ciudad;
  final TipoComprador? tipoComprador;
  final BuyerPreferences preferencias;
  final bool onboardingCompleto;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.rol,
    this.fotoPath,
    this.ciudad,
    this.tipoComprador,
    this.preferencias = const BuyerPreferences(),
    this.onboardingCompleto = false,
    this.createdAt,
    this.updatedAt,
  });

  AppUser copyWith({
    String? nombre,
    String? fotoPath,
    String? ciudad,
    TipoComprador? tipoComprador,
    BuyerPreferences? preferencias,
    bool? onboardingCompleto,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      nombre: nombre ?? this.nombre,
      rol: rol,
      fotoPath: fotoPath ?? this.fotoPath,
      ciudad: ciudad ?? this.ciudad,
      tipoComprador: tipoComprador ?? this.tipoComprador,
      preferencias: preferencias ?? this.preferencias,
      onboardingCompleto: onboardingCompleto ?? this.onboardingCompleto,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Campos editables por el propio usuario (sin `rol`, `uid`, `email` ni
  /// fechas: esos los fija el registro o el servidor).
  Map<String, dynamic> toEditableMap() => {
        'nombre': nombre,
        'fotoPath': fotoPath,
        'ciudad': ciudad,
        'tipoComprador': tipoComprador?.name,
        'preferencias': preferencias.toMap(),
        'onboardingCompleto': onboardingCompleto,
      };

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) {
    return AppUser(
      uid: uid,
      email: readString(m['email']) ?? '',
      nombre: readString(m['nombre']) ?? '',
      rol: readEnum(UserRole.values, m['rol'], UserRole.comprador),
      fotoPath: readString(m['fotoPath']),
      ciudad: readString(m['ciudad']),
      tipoComprador: m['tipoComprador'] is String
          ? readEnum(TipoComprador.values, m['tipoComprador'], TipoComprador.independiente)
          : null,
      preferencias: BuyerPreferences.fromMap(m['preferencias'] as Map<String, dynamic>?),
      onboardingCompleto: m['onboardingCompleto'] == true,
      createdAt: readDate(m['createdAt']),
      updatedAt: readDate(m['updatedAt']),
    );
  }
}
