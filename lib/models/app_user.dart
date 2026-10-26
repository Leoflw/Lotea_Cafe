enum UserRole { comprador, vendedor }

extension UserRoleX on UserRole {
  String get label => this == UserRole.vendedor ? 'Vendedor' : 'Comprador';
}

/// Tipo de negocio del comprador (sección 15 del plan de evolución).
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

/// Preferencias de compra, usadas hoy solo para mostrarlas en "Mi cuenta"
/// y como base para una futura recomendación personalizada (sección 30).
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
}

/// Cuenta de la app. La reputación/verificación del VENDEDOR vive aparte en
/// [SellerProfile] para no duplicar datos entre colecciones.
class AppUser {
  final String uid;
  final String email;
  final String nombre;
  final UserRole rol;
  final String? fotoPath;
  final String? ciudad;
  final TipoComprador? tipoComprador;
  final BuyerPreferences preferencias;

  AppUser({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.rol,
    this.fotoPath,
    this.ciudad,
    this.tipoComprador,
    this.preferencias = const BuyerPreferences(),
  });

  AppUser copyWith({
    String? nombre,
    String? fotoPath,
    String? ciudad,
    TipoComprador? tipoComprador,
    BuyerPreferences? preferencias,
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
    );
  }
}
