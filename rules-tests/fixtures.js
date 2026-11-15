// Documentos de prueba con el ESQUEMA REAL de la app (no versiones recortadas).
//
// `loteReal` reproduce lo que escribe `CoffeeLot.toEditableMap()` + el repositorio (sellerId, nombre,
// variedades, proceso, tipoCafe, altitudMsnm, puntajeTaza, cosecha, perfilSensorial, descripcion,
// precioCOP, unidad, cantidadDisponibleKg, pedidoMinimoKg, disponible, metodosEnvio, certificaciones,
// fotos, fotosStoragePaths, sellerNombreMarca, departamento, region, municipio, estado,
// vendedorVerificado, fechaPublicacion, createdAt, updatedAt). Los lotes reales SIEMPRE tienen estos
// campos: la regla `create` de coffeeLots exige `variedades` (lista no vacía), `precioCOP`, `unidad`,
// `estado`, `fotos`, `fotosStoragePaths`, `descripcion` y `nombre`, y la regla `update` los vuelve a
// evaluar. Un lote de prueba al que le falten no se puede actualizar ni siquiera por su dueño.
export const loteReal = (sobrescribir = {}) => ({
  sellerId: 'ana',
  nombre: 'Caturra Lavado',
  variedades: ['Caturra'],
  proceso: 'Lavado',
  tipoCafe: 'Especial',
  altitudMsnm: 1750,
  puntajeTaza: 84,
  cosecha: '2026',
  perfilSensorial: { dulzor: 4, acidez: 3, cuerpo: 3, amargor: 2, aroma: 4 },
  descripcion: 'Lote de prueba',
  precioCOP: 32000,
  unidad: 'kg',
  cantidadDisponibleKg: 100,
  pedidoMinimoKg: 5,
  disponible: true,
  metodosEnvio: ['Mensajería'],
  certificaciones: [],
  fotos: [],
  fotosStoragePaths: [],
  sellerNombreMarca: 'Finca La Esperanza',
  departamento: 'Huila',
  region: 'Huila',
  municipio: 'Pitalito',
  estado: 'publicado',
  vendedorVerificado: false,
  fechaPublicacion: new Date('2026-11-01T00:00:00Z'),
  createdAt: new Date('2026-11-01T00:00:00Z'),
  updatedAt: new Date('2026-11-01T00:00:00Z'),
  ...sobrescribir,
});

/**
 * Perfil de vendedor con el ESQUEMA REAL: lo que escribe `SellerProfile.toEditableMap()` más lo que fija
 * la creación (`verificado`, `calificacionPromedio`, `numOperaciones`, `createdAt`, `updatedAt`). La regla
 * `update` de sellerProfiles evalúa nombreMarca, fincaPrincipal, descripcion, historia, galeria y
 * galeriaStoragePaths: un perfil recortado no se puede actualizar ni siquiera por su dueño.
 */
export const perfilReal = (sobrescribir = {}) => ({
  usuarioId: 'ana',
  nombreMarca: 'Finca La Esperanza',
  fincaPrincipal: 'La Esperanza',
  fotoPrincipal: null,
  fotoPrincipalStoragePath: null,
  galeria: [],
  galeriaStoragePaths: [],
  descripcion: 'Perfil de prueba',
  historia: 'Historia de prueba',
  aniosProduciendo: 10,
  tipoProduccion: 'Familiar',
  region: 'Huila',
  departamento: 'Huila',
  municipio: 'Pitalito',
  telefonoContacto: '3000000000',
  verificado: false,
  calificacionPromedio: 0,
  numOperaciones: 0,
  createdAt: new Date('2026-11-01T00:00:00Z'),
  updatedAt: new Date('2026-11-01T00:00:00Z'),
  ...sobrescribir,
});

/** Campos que la app envía al guardar un perfil (los demás los fija el servidor o un proceso interno). */
export const CAMPOS_EDITABLES_DE_PERFIL = [
  'usuarioId', 'nombreMarca', 'fincaPrincipal', 'fotoPrincipal', 'fotoPrincipalStoragePath', 'galeria', 'galeriaStoragePaths',
  'descripcion', 'historia', 'aniosProduciendo', 'tipoProduccion', 'region', 'departamento', 'municipio', 'telefonoContacto',
];

/** Campos que las reglas de coffeeLots evalúan siempre al crear o actualizar un lote. */
export const CAMPOS_OBLIGATORIOS_DE_LOTE = ['sellerId', 'nombre', 'variedades', 'precioCOP', 'unidad', 'estado', 'fotos', 'fotosStoragePaths', 'descripcion'];
