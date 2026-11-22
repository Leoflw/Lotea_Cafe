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

/// Estado de la cuenta (`users/{uid}.cuentaEstado`), escrito SOLO por el Worker de limpieza.
/// Campo ausente = activa (usuarios anteriores a la etapa 6). Un valor desconocido es
/// [desconocida]: se trata de forma conservadora (operaciones bloqueadas), nunca como activa.
///
/// [eliminando]: el Worker ya comenzó el borrado definitivo (etapa 7). A diferencia de
/// [eliminacionPendiente] no hay periodo de espera ni cancelación. Hoy ningún proceso lo escribe;
/// la app solo lo reconoce para mostrarlo bien.
enum CuentaEstado { activa, eliminacionPendiente, eliminando, desconocida }

CuentaEstado leerCuentaEstado(Object? v) {
  if (v == null) return CuentaEstado.activa;
  if (v == 'activa') return CuentaEstado.activa;
  if (v == 'eliminacionPendiente') return CuentaEstado.eliminacionPendiente;
  if (v == 'eliminando') return CuentaEstado.eliminando;
  return CuentaEstado.desconocida;
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

  /// Control de la cuenta: SOLO LECTURA. No entra en [toEditableMap] ni en `UserRepository.actualizar`.
  final CuentaEstado cuentaEstado;
  final DateTime? eliminacionSolicitadaAt;
  final DateTime? eliminacionProgramadaAt;

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
    this.cuentaEstado = CuentaEstado.activa,
    this.eliminacionSolicitadaAt,
    this.eliminacionProgramadaAt,
  });

  bool get cuentaActiva => cuentaEstado == CuentaEstado.activa;
  bool get eliminacionPendiente => cuentaEstado == CuentaEstado.eliminacionPendiente;
  bool get eliminando => cuentaEstado == CuentaEstado.eliminando;

  /// Las operaciones comerciales solo se permiten con la cuenta activa (las reglas de Firestore lo exigen).
  bool get operacionesBloqueadas => !cuentaActiva;

  /// El plazo de espera terminó (la etapa 7 todavía no ejecuta el borrado: la solicitud queda pendiente de procesamiento).
  bool plazoVencido(DateTime ahora) {
    final programada = eliminacionProgramadaAt;
    return programada != null && !ahora.isBefore(programada);
  }

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
      cuentaEstado: cuentaEstado,
      eliminacionSolicitadaAt: eliminacionSolicitadaAt,
      eliminacionProgramadaAt: eliminacionProgramadaAt,
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
      cuentaEstado: leerCuentaEstado(m['cuentaEstado']),
      eliminacionSolicitadaAt: readDate(m['eliminacionSolicitadaAt']),
      eliminacionProgramadaAt: readDate(m['eliminacionProgramadaAt']),
    );
  }
}
