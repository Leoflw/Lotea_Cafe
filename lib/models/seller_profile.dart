import '../data/codec.dart';

/// Documento `sellerProfiles/{uid}` — perfil público del vendedor. El id del
/// documento es el UID del propietario, así `sellerId == usuarioId`.
///
/// `verificado`, `calificacionPromedio` y `numOperaciones` NO los puede
/// escribir el cliente (las reglas lo impiden). Hasta que exista un proceso
/// real de verificación y de calificaciones, valen `false`, `0` y `0`, y la
/// interfaz solo los muestra cuando hay datos.
class SellerProfile {
  final String id;
  final String usuarioId;
  final String nombreMarca;
  final String fincaPrincipal;
  final String? fotoPrincipal; // URL pública de ImageKit
  // `fileId` de ImageKit (el nombre `...StoragePath` se conserva para no cambiar
  // el esquema ni las reglas de Firestore).
  final String? fotoPrincipalStoragePath;
  final List<String> galeria; // URLs públicas de ImageKit
  final List<String> galeriaStoragePaths; // fileId de cada foto de la galería
  final String descripcion;
  final String historia;
  final int? aniosProduciendo;
  final String? tipoProduccion;
  final String region;
  final String departamento;
  final String municipio;
  final String? telefonoContacto;
  final bool verificado;
  final double calificacionPromedio;
  final int numOperaciones;
  final DateTime? fechaRegistro;
  final DateTime? updatedAt;

  const SellerProfile({
    required this.id,
    required this.usuarioId,
    required this.nombreMarca,
    required this.fincaPrincipal,
    this.fotoPrincipal,
    this.fotoPrincipalStoragePath,
    this.galeria = const [],
    this.galeriaStoragePaths = const [],
    this.descripcion = '',
    this.historia = '',
    this.aniosProduciendo,
    this.tipoProduccion,
    required this.region,
    required this.departamento,
    this.municipio = '',
    this.telefonoContacto,
    this.verificado = false,
    this.calificacionPromedio = 0.0,
    this.numOperaciones = 0,
    this.fechaRegistro,
    this.updatedAt,
  });

  String get ubicacionCorta =>
      municipio.isNotEmpty ? '$municipio, $departamento' : '$region, $departamento';

  bool get perfilCompleto =>
      nombreMarca.isNotEmpty &&
      fincaPrincipal.isNotEmpty &&
      descripcion.isNotEmpty &&
      historia.isNotEmpty;

  bool get tieneCalificaciones => numOperaciones > 0 && calificacionPromedio > 0;

  SellerProfile copyWith({
    String? nombreMarca,
    String? fincaPrincipal,
    String? fotoPrincipal,
    String? fotoPrincipalStoragePath,
    List<String>? galeria,
    List<String>? galeriaStoragePaths,
    String? descripcion,
    String? historia,
    int? aniosProduciendo,
    String? tipoProduccion,
    String? region,
    String? departamento,
    String? municipio,
    String? telefonoContacto,
  }) {
    return SellerProfile(
      id: id,
      usuarioId: usuarioId,
      nombreMarca: nombreMarca ?? this.nombreMarca,
      fincaPrincipal: fincaPrincipal ?? this.fincaPrincipal,
      fotoPrincipal: fotoPrincipal ?? this.fotoPrincipal,
      fotoPrincipalStoragePath: fotoPrincipalStoragePath ?? this.fotoPrincipalStoragePath,
      galeria: galeria ?? this.galeria,
      galeriaStoragePaths: galeriaStoragePaths ?? this.galeriaStoragePaths,
      descripcion: descripcion ?? this.descripcion,
      historia: historia ?? this.historia,
      aniosProduciendo: aniosProduciendo ?? this.aniosProduciendo,
      tipoProduccion: tipoProduccion ?? this.tipoProduccion,
      region: region ?? this.region,
      departamento: departamento ?? this.departamento,
      municipio: municipio ?? this.municipio,
      telefonoContacto: telefonoContacto ?? this.telefonoContacto,
      verificado: verificado,
      calificacionPromedio: calificacionPromedio,
      numOperaciones: numOperaciones,
      fechaRegistro: fechaRegistro,
      updatedAt: updatedAt,
    );
  }

  /// Solo campos que el vendedor puede escribir.
  Map<String, dynamic> toEditableMap() => {
        'usuarioId': usuarioId,
        'nombreMarca': nombreMarca,
        'fincaPrincipal': fincaPrincipal,
        'fotoPrincipal': fotoPrincipal,
        'fotoPrincipalStoragePath': fotoPrincipalStoragePath,
        'galeria': galeria,
        'galeriaStoragePaths': galeriaStoragePaths,
        'descripcion': descripcion,
        'historia': historia,
        'aniosProduciendo': aniosProduciendo,
        'tipoProduccion': tipoProduccion,
        'region': region,
        'departamento': departamento,
        'municipio': municipio,
        'telefonoContacto': telefonoContacto,
      };

  factory SellerProfile.fromMap(String id, Map<String, dynamic> m) {
    return SellerProfile(
      id: id,
      usuarioId: readString(m['usuarioId']) ?? id,
      nombreMarca: readString(m['nombreMarca']) ?? '',
      fincaPrincipal: readString(m['fincaPrincipal']) ?? '',
      fotoPrincipal: readString(m['fotoPrincipal']),
      fotoPrincipalStoragePath: readString(m['fotoPrincipalStoragePath']),
      galeria: readStringList(m['galeria']),
      galeriaStoragePaths: readStringList(m['galeriaStoragePaths']),
      descripcion: readString(m['descripcion']) ?? '',
      historia: readString(m['historia']) ?? '',
      aniosProduciendo: readInt(m['aniosProduciendo']),
      tipoProduccion: readString(m['tipoProduccion']),
      region: readString(m['region']) ?? readString(m['departamento']) ?? '',
      departamento: readString(m['departamento']) ?? '',
      municipio: readString(m['municipio']) ?? '',
      telefonoContacto: readString(m['telefonoContacto']),
      verificado: m['verificado'] == true,
      calificacionPromedio: readDouble(m['calificacionPromedio']) ?? 0.0,
      numOperaciones: readInt(m['numOperaciones']) ?? 0,
      fechaRegistro: readDate(m['createdAt']),
      updatedAt: readDate(m['updatedAt']),
    );
  }
}

/// Departamentos usados en filtros y formularios.
const List<String> departamentosColombia = [
  'Huila',
  'Antioquia',
  'Nariño',
  'Caldas',
  'Quindío',
  'Tolima',
  'Cauca',
  'Valle del Cauca',
];
