import '../data/codec.dart';

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

  Map<String, dynamic> toMap() => {
        'notas': notas,
        'acidez': acidez,
        'cuerpo': cuerpo,
        'dulzor': dulzor,
      };

  factory TasteProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const TasteProfile();
    return TasteProfile(
      notas: readStringList(m['notas']),
      acidez: readString(m['acidez']),
      cuerpo: readString(m['cuerpo']),
      dulzor: readString(m['dulzor']),
    );
  }
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
  final List<String> fotos; // URLs públicas de ImageKit (solo fotos subidas con éxito)
  // `fileId` de ImageKit de cada foto (misma posición que `fotos`). Conserva el
  // nombre `fotosStoragePaths` para no cambiar el esquema ni las reglas de Firestore.
  final List<String> fotosStoragePaths;
  // Datos del vendedor copiados al publicar, para listar y filtrar sin leer
  // un documento por tarjeta. `vendedorVerificado` NO lo escribe el cliente.
  final String sellerNombreMarca;
  final String departamento;
  final String region;
  final String municipio;
  final bool vendedorVerificado;
  final EstadoLote estado;
  final DateTime? fechaPublicacion;
  final DateTime? updatedAt;

  const CoffeeLot({
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
    this.fotosStoragePaths = const [],
    this.sellerNombreMarca = '',
    this.departamento = '',
    this.region = '',
    this.municipio = '',
    this.vendedorVerificado = false,
    this.estado = EstadoLote.borrador,
    this.fechaPublicacion,
    this.updatedAt,
  });

  bool get publicado => estado == EstadoLote.publicado;

  /// Hay al menos una foto realmente subida (URL remota). Una ruta local de
  /// una subida fallida no cuenta.
  bool get tieneFoto => fotos.any((f) => f.startsWith('https://') || f.startsWith('http://'));
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
    List<String>? fotosStoragePaths,
    String? sellerNombreMarca,
    String? departamento,
    String? region,
    String? municipio,
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
      fotosStoragePaths: fotosStoragePaths ?? this.fotosStoragePaths,
      sellerNombreMarca: sellerNombreMarca ?? this.sellerNombreMarca,
      departamento: departamento ?? this.departamento,
      region: region ?? this.region,
      municipio: municipio ?? this.municipio,
      vendedorVerificado: vendedorVerificado,
      estado: estado ?? this.estado,
      // La fecha de publicación la fija el servidor (ver CoffeeLotRepository).
      fechaPublicacion: fechaPublicacion,
      updatedAt: updatedAt,
    );
  }

  /// Campos que escribe el cliente. Las fechas (`fechaPublicacion`,
  /// `createdAt`, `updatedAt`) las añade el repositorio con hora de servidor.
  Map<String, dynamic> toEditableMap() => {
        'sellerId': sellerId,
        'nombre': nombre,
        'variedades': variedades,
        'proceso': proceso,
        'tipoCafe': tipoCafe,
        'altitudMsnm': altitudMsnm,
        'puntajeTaza': puntajeTaza,
        'cosecha': cosecha,
        'perfilSensorial': perfilSensorial.toMap(),
        'descripcion': descripcion,
        'precioCOP': precioCOP,
        'unidad': unidad,
        'cantidadDisponibleKg': cantidadDisponibleKg,
        'pedidoMinimoKg': pedidoMinimoKg,
        'disponible': disponible,
        'metodosEnvio': metodosEnvio,
        'certificaciones': certificaciones,
        'fotos': fotos,
        'fotosStoragePaths': fotosStoragePaths,
        'sellerNombreMarca': sellerNombreMarca,
        'departamento': departamento,
        'region': region,
        'municipio': municipio,
        'estado': estado.name,
      };

  factory CoffeeLot.fromMap(String id, Map<String, dynamic> m) {
    return CoffeeLot(
      id: id,
      sellerId: readString(m['sellerId']) ?? '',
      nombre: readString(m['nombre']) ?? '',
      variedades: readStringList(m['variedades']),
      proceso: readString(m['proceso']) ?? '',
      tipoCafe: readString(m['tipoCafe']),
      altitudMsnm: readDouble(m['altitudMsnm']),
      puntajeTaza: readDouble(m['puntajeTaza']),
      cosecha: readString(m['cosecha']),
      perfilSensorial: TasteProfile.fromMap(m['perfilSensorial'] as Map<String, dynamic>?),
      descripcion: readString(m['descripcion']) ?? '',
      precioCOP: readDouble(m['precioCOP']) ?? 0,
      unidad: readString(m['unidad']) ?? 'kg',
      cantidadDisponibleKg: readDouble(m['cantidadDisponibleKg']),
      pedidoMinimoKg: readDouble(m['pedidoMinimoKg']),
      disponible: m['disponible'] != false,
      metodosEnvio: readStringList(m['metodosEnvio']),
      certificaciones: readStringList(m['certificaciones']),
      fotos: readStringList(m['fotos']),
      fotosStoragePaths: readStringList(m['fotosStoragePaths']),
      sellerNombreMarca: readString(m['sellerNombreMarca']) ?? '',
      departamento: readString(m['departamento']) ?? '',
      region: readString(m['region']) ?? '',
      municipio: readString(m['municipio']) ?? '',
      vendedorVerificado: m['vendedorVerificado'] == true,
      estado: readEnum(EstadoLote.values, m['estado'], EstadoLote.borrador),
      fechaPublicacion: readDate(m['fechaPublicacion']),
      updatedAt: readDate(m['updatedAt']),
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
