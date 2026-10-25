enum DiscoverSort { relevancia, precioAsc, precioDesc, puntajeDesc, recientes, disponibilidad }

extension DiscoverSortX on DiscoverSort {
  String get label {
    switch (this) {
      case DiscoverSort.relevancia:
        return 'Más relevantes';
      case DiscoverSort.precioAsc:
        return 'Precio: menor a mayor';
      case DiscoverSort.precioDesc:
        return 'Precio: mayor a menor';
      case DiscoverSort.puntajeDesc:
        return 'Mayor puntaje';
      case DiscoverSort.recientes:
        return 'Más recientes';
      case DiscoverSort.disponibilidad:
        return 'Mayor disponibilidad';
    }
  }
}

/// Filtros de descubrimiento. Se aplican sobre los lotes publicados que trae
/// Firestore (ver CoffeeLotRepository.consultarCatalogo y CatalogLogic).
class DiscoverFilters {
  final List<String> departamentos;
  final List<String> variedades;
  final List<String> procesos;
  final double? precioMinCOP;
  final double? precioMaxCOP;
  final double? altitudMin;
  final double? altitudMax;
  final double? puntajeMin;
  final List<String> certificaciones;
  final bool soloDisponibles;
  final String? tipoCafe;
  final bool soloVerificados;
  final String busqueda;
  final DiscoverSort orden;

  const DiscoverFilters({
    this.departamentos = const [],
    this.variedades = const [],
    this.procesos = const [],
    this.precioMinCOP,
    this.precioMaxCOP,
    this.altitudMin,
    this.altitudMax,
    this.puntajeMin,
    this.certificaciones = const [],
    this.soloDisponibles = false,
    this.tipoCafe,
    this.soloVerificados = false,
    this.busqueda = '',
    this.orden = DiscoverSort.relevancia,
  });

  DiscoverFilters copyWith({
    List<String>? departamentos,
    List<String>? variedades,
    List<String>? procesos,
    double? precioMinCOP,
    double? precioMaxCOP,
    double? altitudMin,
    double? altitudMax,
    double? puntajeMin,
    List<String>? certificaciones,
    bool? soloDisponibles,
    String? tipoCafe,
    bool? soloVerificados,
    String? busqueda,
    DiscoverSort? orden,
  }) {
    return DiscoverFilters(
      departamentos: departamentos ?? this.departamentos,
      variedades: variedades ?? this.variedades,
      procesos: procesos ?? this.procesos,
      precioMinCOP: precioMinCOP ?? this.precioMinCOP,
      precioMaxCOP: precioMaxCOP ?? this.precioMaxCOP,
      altitudMin: altitudMin ?? this.altitudMin,
      altitudMax: altitudMax ?? this.altitudMax,
      puntajeMin: puntajeMin ?? this.puntajeMin,
      certificaciones: certificaciones ?? this.certificaciones,
      soloDisponibles: soloDisponibles ?? this.soloDisponibles,
      tipoCafe: tipoCafe ?? this.tipoCafe,
      soloVerificados: soloVerificados ?? this.soloVerificados,
      busqueda: busqueda ?? this.busqueda,
      orden: orden ?? this.orden,
    );
  }

  /// Cantidad de GRUPOS de filtro activos (la búsqueda y el orden no cuentan).
  int get numFiltrosActivos =>
      (departamentos.isNotEmpty ? 1 : 0) +
      (variedades.isNotEmpty ? 1 : 0) +
      (procesos.isNotEmpty ? 1 : 0) +
      ((precioMinCOP != null || precioMaxCOP != null) ? 1 : 0) +
      ((altitudMin != null || altitudMax != null) ? 1 : 0) +
      (puntajeMin != null ? 1 : 0) +
      (certificaciones.isNotEmpty ? 1 : 0) +
      (soloDisponibles ? 1 : 0) +
      (tipoCafe != null ? 1 : 0) +
      (soloVerificados ? 1 : 0);

  bool get tieneFiltrosActivos => numFiltrosActivos > 0;
  bool get hayBusqueda => busqueda.trim().isNotEmpty;
}
