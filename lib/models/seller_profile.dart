/// Información del VENDEDOR/marca — separada de sus cafés (ver [CoffeeLot]).
/// Un vendedor tiene un único SellerProfile pero puede publicar varios lotes.
class SellerProfile {
  final String id; // == usuarioId (relación 1:1 con la cuenta)
  final String usuarioId;
  final String nombreMarca;
  final String fincaPrincipal;
  final String? fotoPrincipal; // ruta local
  final List<String> galeria; // fotos de finca, cafetal, proceso, empaque...
  final String descripcion;
  final String historia; // "Sobre el productor"
  final int? aniosProduciendo;
  final String? tipoProduccion; // familiar, cooperativa, tecnificada...
  final String region;
  final String departamento;
  final String municipio;
  final String? telefonoContacto;
  final bool verificado;
  final double calificacionPromedio;
  final int numOperaciones;
  final DateTime fechaRegistro;

  SellerProfile({
    required this.id,
    required this.usuarioId,
    required this.nombreMarca,
    required this.fincaPrincipal,
    this.fotoPrincipal,
    this.galeria = const [],
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
    DateTime? fechaRegistro,
  }) : fechaRegistro = fechaRegistro ?? DateTime.now();

  String get ubicacionCorta =>
      municipio.isNotEmpty ? '$municipio, $departamento' : '$region, $departamento';

  bool get perfilCompleto =>
      descripcion.isNotEmpty && historia.isNotEmpty && galeria.isNotEmpty;

  SellerProfile copyWith({
    String? nombreMarca,
    String? fincaPrincipal,
    String? fotoPrincipal,
    List<String>? galeria,
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
      galeria: galeria ?? this.galeria,
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
    );
  }
}

/// Departamentos usados en filtros y formularios (datos de demo de Colombia).
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
