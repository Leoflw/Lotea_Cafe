// Acceso a Firestore por su API REST con la cuenta de servicio de este Worker.
// Solo toca:
//  - las colas users/{uid}/pendingFileDeletions y users/{uid}/pendingLotDeletions
//    (leer y actualizar su estado; crear solicitudes de foto de un lote que se elimina);
//  - en SOLO LECTURA, coffeeLots, sellerProfiles, interestRequests y quotes para
//    comprobar si una foto sigue en uso;
//  - ÚNICA escritura sobre datos de negocio: poner `loteFoto = null` (solo ese campo,
//    con máscara) en las solicitudes y cotizaciones del propio vendedor cuando elimina
//    el lote, y borrar ese lote. Nunca otro campo ni documentos de otra persona.

import { ErrorTemporal } from './errores.js';
import { fetchConCuenta } from './google-auth.js';

export const raiz = (p) => `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(p)}/databases/(default)/documents`;
export const ruta = (p, ...seg) => `${raiz(p)}/${seg.map((s) => encodeURIComponent(s)).join('/')}`;

// ---- Valores REST ----
export const vTexto = (s) => ({ stringValue: s });
export const vEntero = (n) => ({ integerValue: String(Math.trunc(n)) });
export const vTiempo = (ms) => ({ timestampValue: new Date(ms).toISOString() });
export const vNulo = () => ({ nullValue: null });

export const texto = (doc, campo) => doc?.fields?.[campo]?.stringValue ?? null;
export const entero = (doc, campo) => {
  const v = doc?.fields?.[campo]?.integerValue;
  return v === undefined ? 0 : Number(v);
};
export function marcaMs(doc, campo) {
  const v = doc?.fields?.[campo]?.timestampValue;
  if (typeof v !== 'string') return null;
  const ms = Date.parse(v);
  return Number.isNaN(ms) ? null : ms;
}

/** Id (último segmento) y uid (segmento tras `users`) de una ruta de la cola. */
export function partesDeCola(nombreDoc, coleccion = 'pendingFileDeletions') {
  const seg = String(nombreDoc).split('/');
  const i = seg.indexOf('users');
  if (i < 0 || seg[i + 2] !== coleccion) return null;
  return { uid: seg[i + 1], id: seg[seg.length - 1] };
}

export const nombreDoc = (proyecto, ...seg) => `projects/${proyecto}/databases/(default)/documents/${seg.join('/')}`;

export async function comoJson(resp, codigo) {
  if (resp.status === 429 || resp.status >= 500) throw new ErrorTemporal(`${codigo}_${resp.status === 429 ? '429' : '5xx'}`);
  if (!resp.ok) throw new ErrorTemporal(`${codigo}_${resp.status}`);
  try {
    return await resp.json();
  } catch {
    throw new ErrorTemporal(`${codigo}_respuesta`);
  }
}

/** Solicitudes de un usuario (la UID sale del token verificado, nunca del cliente). */
export async function listarColaDeUsuario(env, uid, deps, coleccion = 'pendingFileDeletions') {
  const url = `${ruta(env.FIREBASE_PROJECT_ID, 'users', uid, coleccion)}?pageSize=50`;
  const resp = await fetchConCuenta(env, url, { method: 'GET' }, deps);
  if (resp.status === 404) return [];
  const { documents = [] } = await comoJson(resp, 'firestore_listar');
  return documents;
}

/** Solicitudes de TODOS los usuarios en un estado (consulta de grupo de colección; solo para el cron). */
export async function listarColaGlobal(env, estado, limite, deps, coleccion = 'pendingFileDeletions') {
  const url = `${raiz(env.FIREBASE_PROJECT_ID)}:runQuery`;
  const cuerpo = {
    structuredQuery: {
      from: [{ collectionId: coleccion, allDescendants: true }],
      where: { fieldFilter: { field: { fieldPath: 'estado' }, op: 'EQUAL', value: vTexto(estado) } },
      limit: limite,
    },
  };
  const resp = await fetchConCuenta(env, url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo) }, deps);
  const filas = await comoJson(resp, 'firestore_cola_global');
  return (Array.isArray(filas) ? filas : []).map((f) => f.document).filter(Boolean);
}

/**
 * Actualiza campos de un documento de la cola. Con [updateTime] solo se aplica si
 * el documento no cambió desde que se leyó (precondición): evita que dos
 * ejecuciones procesen lo mismo a la vez. Devuelve el documento actualizado o
 * null si la precondición falló.
 */
export async function actualizarCola(env, uid, id, campos, { updateTime, coleccion = 'pendingFileDeletions' } = {}, deps) {
  const mascara = Object.keys(campos).map((c) => `updateMask.fieldPaths=${encodeURIComponent(c)}`);
  const fields = {};
  for (const [k, v] of Object.entries(campos)) if (v !== undefined && v !== null && !('nullValue' in v)) fields[k] = v;
  const precond = updateTime ? `currentDocument.updateTime=${encodeURIComponent(updateTime)}` : 'currentDocument.exists=true';
  const url = `${ruta(env.FIREBASE_PROJECT_ID, 'users', uid, coleccion, id)}?${[...mascara, precond].join('&')}`;
  const resp = await fetchConCuenta(env, url, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ fields }) }, deps);
  if (resp.status === 409 || resp.status === 412 || resp.status === 404) return null;
  return comoJson(resp, 'firestore_actualizar');
}

const filtroArray = (campo, valor) => ({ fieldFilter: { field: { fieldPath: campo }, op: 'ARRAY_CONTAINS', value: vTexto(valor) } });
const filtroIgual = (campo, valor) => ({ fieldFilter: { field: { fieldPath: campo }, op: 'EQUAL', value: vTexto(valor) } });
const filtroOp = (campo, op, valor) => ({ fieldFilter: { field: { fieldPath: campo }, op, value: vTexto(valor) } });
const unirO = (filtros) => (filtros.length === 1 ? filtros[0] : { compositeFilter: { op: 'OR', filters: filtros } });
const unirY = (filtros) => ({ compositeFilter: { op: 'AND', filters: filtros } });

async function consultar(env, coleccion, where, limite, deps, codigo) {
  const cuerpo = { structuredQuery: { from: [{ collectionId: coleccion }], where, limit: limite } };
  const resp = await fetchConCuenta(
    env,
    `${raiz(env.FIREBASE_PROJECT_ID)}:runQuery`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo) },
    deps,
  );
  const filas = await comoJson(resp, codigo);
  return (Array.isArray(filas) ? filas : []).map((f) => f.document).filter(Boolean);
}

/**
 * ¿Quién sigue usando esta foto? Devuelve
 *   'actual'    un lote o perfil VIGENTE la referencia (por fileId o por URL),
 *   'historica' solo la copia `loteFoto` de una solicitud de interés o cotización la usa,
 *   null        nadie.
 * Se mira en TODOS los documentos, no solo los del usuario: ante la duda NO se borra.
 * La URL histórica se compara por PREFIJO (cubre una URL con parámetros añadidos).
 * Cualquier fallo de consulta lanza [ErrorTemporal] y la foto no se borra («fallar cerrado»).
 */
export async function referenciadaPor(env, { fileId, url }, deps) {
  const lotes = [filtroArray('fotosStoragePaths', fileId), filtroArray('fotos', url)];
  const perfiles = [
    filtroArray('galeriaStoragePaths', fileId),
    filtroIgual('fotoPrincipalStoragePath', fileId),
    filtroArray('galeria', url),
    filtroIgual('fotoPrincipal', url),
  ];
  if ((await consultar(env, 'coffeeLots', unirO(lotes), 1, deps, 'firestore_referencias')).length) return 'actual';
  if ((await consultar(env, 'sellerProfiles', unirO(perfiles), 1, deps, 'firestore_referencias')).length) return 'actual';
  const historica = unirY([filtroOp('loteFoto', 'GREATER_THAN_OR_EQUAL', url), filtroOp('loteFoto', 'LESS_THAN_OR_EQUAL', `${url}\uf8ff`)]);
  if ((await consultar(env, 'interestRequests', historica, 1, deps, 'firestore_referencias')).length) return 'historica';
  if ((await consultar(env, 'quotes', historica, 1, deps, 'firestore_referencias')).length) return 'historica';
  return null;
}

// ---- Eliminación de un lote (solicitud users/{uid}/pendingLotDeletions/{lotId}) ----

/** Lote por id (cuenta de servicio) o null si no existe. */
export async function leerLote(env, lotId, deps) {
  const resp = await fetchConCuenta(env, ruta(env.FIREBASE_PROJECT_ID, 'coffeeLots', lotId), { method: 'GET' }, deps);
  if (resp.status === 404) return null;
  return comoJson(resp, 'firestore_leer_lote');
}

export async function borrarLote(env, lotId, deps) {
  const resp = await fetchConCuenta(env, ruta(env.FIREBASE_PROJECT_ID, 'coffeeLots', lotId), { method: 'DELETE' }, deps);
  if (resp.status === 404) return;
  if (!resp.ok) throw new ErrorTemporal(`firestore_borrar_lote_${resp.status}`);
}

/**
 * Solicitudes de interés o cotizaciones DEL VENDEDOR sobre este lote que aún tienen
 * `loteFoto`. Los tres filtros (lote, vendedor, loteFoto no nulo) impiden tocar
 * negociaciones ajenas y hacen que lo ya limpiado no vuelva a aparecer (idempotente).
 * Requiere los índices compuestos de firestore.indexes.json.
 */
export async function historicosConFoto(env, coleccion, { lotId, uid }, limite, deps) {
  const where = unirY([
    filtroIgual('coffeeLotId', lotId),
    filtroIgual('sellerId', uid),
    { unaryFilter: { op: 'IS_NOT_NULL', field: { fieldPath: 'loteFoto' } } },
  ]);
  return consultar(env, coleccion, where, limite, deps, 'firestore_historicos');
}

async function confirmar(env, writes, deps, codigo) {
  if (writes.length === 0) return;
  const resp = await fetchConCuenta(
    env,
    `${raiz(env.FIREBASE_PROJECT_ID)}:commit`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ writes }) },
    deps,
  );
  await comoJson(resp, codigo);
}

/** Pone `loteFoto = null` (SOLO ese campo) en los documentos dados, en un único commit atómico. */
export async function anularLoteFoto(env, docs, deps) {
  await confirmar(
    env,
    docs.map((d) => ({ update: { name: d.name, fields: { loteFoto: vNulo() } }, updateMask: { fieldPaths: ['loteFoto'] }, currentDocument: { exists: true } })),
    deps,
    'firestore_anular_foto',
  );
}

/** Crea solicitudes de borrado de foto (pendiente) que aún no existan, en un commit. */
export async function crearSolicitudesDeFoto(env, uid, lotId, fileIds, ahoraMs, deps) {
  const existentes = new Set((await listarColaDeUsuario(env, uid, deps)).map((d) => partesDeCola(d.name)?.id));
  const nuevos = fileIds.filter((id) => !existentes.has(id));
  await confirmar(
    env,
    nuevos.map((id) => ({
      update: {
        name: nombreDoc(env.FIREBASE_PROJECT_ID, 'users', uid, 'pendingFileDeletions', id),
        fields: { fileId: vTexto(id), origen: vTexto('lot'), refId: vTexto(lotId), estado: vTexto('pendiente'), createdAt: vTiempo(ahoraMs) },
      },
      currentDocument: { exists: false },
    })),
    deps,
    'firestore_encolar_fotos',
  );
  return nuevos.length;
}

/** Devuelve a «pendiente» las fotos que estaban «retenida» por este lote (ya sin copias históricas). */
export async function liberarRetenidas(env, uid, lotId, ahoraMs, deps) {
  const docs = (await listarColaDeUsuario(env, uid, deps)).filter(
    (d) => texto(d, 'estado') === 'retenida' && texto(d, 'refId') === lotId,
  );
  await confirmar(
    env,
    docs.map((d) => ({
      update: { name: d.name, fields: { estado: vTexto('pendiente'), intentos: vEntero(0), updatedAt: vTiempo(ahoraMs) } },
      updateMask: { fieldPaths: ['estado', 'intentos', 'updatedAt', 'nextAttemptAt', 'leaseUntil', 'ultimoError'] },
      currentDocument: { exists: true },
    })),
    deps,
    'firestore_liberar_retenidas',
  );
  return docs.length;
}
