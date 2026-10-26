enum EstadoLote { borrador, publicado }

/// Perfil sensorial simplificado (sección 5 — "Perfil de taza").
/// Se usan niveles descriptivos en vez de valores numéricos complejos.
class TasteProfile {
  final List<String> notas; // ej: "Cítrico", "Panela", "Frutos rojos"
  final String? acidez; // Baja / Media / Alta
  final String? cuerpo; // Ligero / Medio / Intenso
  final String? dulzor; // Bajo / Medio / Alto

  const TasteProfile({
    this.notas = const [],
    this.acidez,
    this.cuerpo,
    this.dulzor,
  });

  bool get estaVacio =>
      notas.isEmpty && acidez == null && cuerpo == null && dulzor == null;
}

const List<String> nivelesSensoriales = ['Bajo', 'Medio', 'Alto'];

/// Un café/lote publicado por un vendedor. Un mismo [SellerProfile] puede
/// tener varios CoffeeLot (ej: "Caturra Lavado", "Geisha Natural").
/// Solo `nombre`, `variedad`, `proceso` y `precioCOP` son obligatorios;
/// el resto es opcional para no bloquear la publicación de un lote simple.
class CoffeeLot {
  final String id;
  final String sellerId;
  final String nombre;
  final List<String> variedades;
  final String proceso;
  final String? tipoCafe; // Especial / Comercial
  final double? altitudMsnm;
  final double? puntajeTaza;
  final String? cosecha; // ej: "2026-1"
  final TasteProfile perfilSensorial;
  final String descripcion;
  final double precioCOP;
  final String unidad; // kg | lb | saco (de 70kg)
  final double? cantidadDisponibleKg;
  final double? pedidoMinimoKg;
  final bool disponible;
  final List<String> metodosEnvio;
  final List<String> certificaciones;
  final List<String> fotos; // rutas locales
  final EstadoLote estado;
  final DateTime? fechaPublicacion;

  CoffeeLot({
    required this.id,
    required this.sellerId,
    required this.nombre,
    required this.variedades,
    required this.proceso,
    this.tipoCafe,
    this.altitudMsnm,
    this.puntajeTaza,
    this.cosecha,
    this.perfilSensorial = const TasteProfile(),
    this.descripcion = '',
    required this.precioCOP,
    this.unidad = 'kg',
    this.cantidadDisponibleKg,
    this.pedidoMinimoKg,
    this.disponible = true,
    this.metodosEnvio = const [],
    this.certificaciones = const [],
    this.fotos = const [],
    this.estado = EstadoLote.borrador,
    this.fechaPublicacion,
  });

  bool get publicado => estado == EstadoLote.publicado;
  String get varietyPrincipal => variedades.isNotEmpty ? variedades.first : '—';

  CoffeeLot copyWith({
    String? nombre,
    List<String>? variedades,
    String? proceso,
    String? tipoCafe,
    double? altitudMsnm,
    double? puntajeTaza,
    String? cosecha,
    TasteProfile? perfilSensorial,
    String? descripcion,
    double? precioCOP,
    String? unidad,
    double? cantidadDisponibleKg,
    double? pedidoMinimoKg,
    bool? disponible,
    List<String>? metodosEnvio,
    List<String>? certificaciones,
    List<String>? fotos,
    EstadoLote? estado,
  }) {
    return CoffeeLot(
      id: id,
      sellerId: sellerId,
      nombre: nombre ?? this.nombre,
      variedades: variedades ?? this.variedades,
      proceso: proceso ?? this.proceso,
      tipoCafe: tipoCafe ?? this.tipoCafe,
      altitudMsnm: altitudMsnm ?? this.altitudMsnm,
      puntajeTaza: puntajeTaza ?? this.puntajeTaza,
      cosecha: cosecha ?? this.cosecha,
      perfilSensorial: perfilSensorial ?? this.perfilSensorial,
      descripcion: descripcion ?? this.descripcion,
      precioCOP: precioCOP ?? this.precioCOP,
      unidad: unidad ?? this.unidad,
      cantidadDisponibleKg: cantidadDisponibleKg ?? this.cantidadDisponibleKg,
      pedidoMinimoKg: pedidoMinimoKg ?? this.pedidoMinimoKg,
      disponible: disponible ?? this.disponible,
      metodosEnvio: metodosEnvio ?? this.metodosEnvio,
      certificaciones: certificaciones ?? this.certificaciones,
      fotos: fotos ?? this.fotos,
      estado: estado ?? this.estado,
      fechaPublicacion:
          (estado == EstadoLote.publicado) ? (fechaPublicacion ?? DateTime.now()) : fechaPublicacion,
    );
  }
}

const List<String> variedadesDisponibles = [
  'Arábica', 'Robusta', 'Geisha', 'Bourbon', 'Typica', 'Caturra', 'Castillo',
];
const List<String> procesosDisponibles = ['Lavado', 'Natural', 'Honey'];
const List<String> tiposCafeDisponibles = ['Especial', 'Comercial'];
const List<String> certificacionesDisponibles = [
  'Orgánico', 'Fair Trade', 'Rainforest Alliance', 'Denominación de origen',
];
const List<String> unidadesDisponibles = ['kg', 'lb', 'saco (70kg)'];
