/// Perfil de café de un vendedor. En esta versión offline las
/// "imágenes" son rutas locales (File.path) elegidas con la galería del
/// teléfono; no se suben a ningún servidor.
class CoffeeProfile {
  final String id;
  final String vendedorId;
  final String nombreVendedor;
  final String finca;
  final List<String> variedades;
  final double? altitudMsnm;
  final String proceso;
  final String descripcion;
  final List<String> imagenes; // rutas locales
  final double precioPorKg;
  final double? inventarioKg;
  final List<String> certificaciones;
  final double calificacionPromedio;
  final bool publicado;

  CoffeeProfile({
    required this.id,
    required this.vendedorId,
    required this.nombreVendedor,
    required this.finca,
    required this.variedades,
    this.altitudMsnm,
    required this.proceso,
    this.descripcion = '',
    this.imagenes = const [],
    required this.precioPorKg,
    this.inventarioKg,
    this.certificaciones = const [],
    this.calificacionPromedio = 0.0,
    this.publicado = false,
  });

  CoffeeProfile copyWith({
    String? nombreVendedor,
    String? finca,
    List<String>? variedades,
    double? altitudMsnm,
    String? proceso,
    String? descripcion,
    List<String>? imagenes,
    double? precioPorKg,
    double? inventarioKg,
    List<String>? certificaciones,
    bool? publicado,
  }) {
    return CoffeeProfile(
      id: id,
      vendedorId: vendedorId,
      nombreVendedor: nombreVendedor ?? this.nombreVendedor,
      finca: finca ?? this.finca,
      variedades: variedades ?? this.variedades,
      altitudMsnm: altitudMsnm ?? this.altitudMsnm,
      proceso: proceso ?? this.proceso,
      descripcion: descripcion ?? this.descripcion,
      imagenes: imagenes ?? this.imagenes,
      precioPorKg: precioPorKg ?? this.precioPorKg,
      inventarioKg: inventarioKg ?? this.inventarioKg,
      certificaciones: certificaciones ?? this.certificaciones,
      calificacionPromedio: calificacionPromedio,
      publicado: publicado ?? this.publicado,
    );
  }
}
