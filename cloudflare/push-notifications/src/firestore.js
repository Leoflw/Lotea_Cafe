// Acceso a Firestore por su API REST.
//
// Hay DOS formas de acceso, a propósito:
//  - Lecturas «como el usuario» (leerComoUsuario): con el ID token del propio
//    usuario. Las reglas de seguridad de Firestore deciden si puede ver la
//    conexión, el mensaje, la cotización o el evento: el Worker nunca amplía
//    lo que esa persona ya podría leer desde la app.
//  - Accesos con la cuenta de servicio (resto de funciones): SOLO para los
//    tokens de dispositivo del destinatario (users/{uid}/deviceTokens) y los
//    registros de deduplicación (pushDedupe). El Worker no toca nada más.

import { diagExcepcion, diagHttp } from './diagnostico.js';
import { UpstreamError } from './errores.js';
import { fetchConCuenta } from './google-auth.js';

const raiz = (proyecto) =>
  `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(proyecto)}/databases/(default)/documents`;

/** Ruta REST de un documento o colección; cada segmento se codifica. */
export function ruta(proyecto, ...segmentos) {
  return `${raiz(proyecto)}/${segmentos.map((s) => encodeURIComponent(s)).join('/')}`;
}

// ---- Lectura de valores de documentos REST ----
export const texto = (doc, campo) => doc?.fields?.[campo]?.stringValue ?? null;

/** Marca de tiempo (ms desde 1970) o null si falta o no se puede interpretar. */
export function marcaMs(doc, campo) {
  const v = doc?.fields?.[campo]?.timestampValue;
  if (typeof v !== 'string') return null;
  const ms = Date.parse(v);
  return Number.isNaN(ms) ? null : ms;
}

export const entero = (doc, campo) => {
  const v = doc?.fields?.[campo]?.integerValue;
  return v === undefined ? null : Number(v);
};

/**
 * Lee un documento con el ID token del usuario.
 * Devuelve { estado: 'ok', doc } | { estado: 'noEncontrado' } | { estado: 'prohibido' }.
 * [objeto] (opcional: 'conexion' | 'mensaje' | 'cotizacion' | 'evento') solo
 * sirve para el diagnóstico.
 */
export async function leerComoUsuario(proyecto, segmentos, idToken, fetchFn, objeto) {
  const extra = objeto ? { objeto } : {};
  let resp;
  try {
    resp = await fetchFn(ruta(proyecto, ...segmentos), { headers: { Authorization: `Bearer ${idToken}` } });
  } catch (e) {
    throw new UpstreamError('No se pudo contactar con Firestore.', diagExcepcion('firestore_leer_evento', e, extra));
  }
  if (resp.status === 404) return { estado: 'noEncontrado' };
  if (resp.status === 403 || resp.status === 401) return { estado: 'prohibido' };
  if (!resp.ok) throw new UpstreamError(`Firestore respondió ${resp.status}.`, await diagHttp('firestore_leer_evento', resp, extra));
  return { estado: 'ok', doc: await resp.json() };
}

// ---- Tokens de dispositivo (cuenta de servicio) ----
const MAX_DISPOSITIVOS = 10; // limita subpeticiones por invocación (plan gratuito: 50)

/** Dispositivos del destinatario, el más reciente primero. */
export async function listarDispositivos(env, proyecto, uid, deps) {
  const url = `${ruta(proyecto, 'users', uid, 'deviceTokens')}?pageSize=20`;
  const resp = await fetchConCuenta(env, url, { method: 'GET' }, deps, 'firestore_listar_dispositivos');
  if (resp.status === 404) return [];
  if (!resp.ok) throw new UpstreamError(`Firestore respondió ${resp.status} al leer dispositivos.`, await diagHttp('firestore_listar_dispositivos', resp));
  const { documents = [] } = await resp.json();
  return documents
    .map((d) => ({
      id: d.name.split('/').pop(),
      token: texto(d, 'token'),
      updateTime: d.updateTime ?? null,
      updatedAtMs: marcaMs(d, 'updatedAt') ?? 0,
    }))
    .filter((d) => typeof d.token === 'string' && d.token.length >= 20 && d.token.length <= 4096)
    .sort((a, b) => b.updatedAtMs - a.updatedAtMs)
    .slice(0, MAX_DISPOSITIVOS);
}

/**
 * Borra el registro de un dispositivo SOLO si no cambió desde que se leyó
 * (precondición por updateTime): un token renovado entretanto no se pierde.
 * Cualquier fallo se ignora: borrar es una limpieza, no algo crítico.
 */
export async function borrarDispositivo(env, proyecto, uid, dispositivo, deps) {
  const base = ruta(proyecto, 'users', uid, 'deviceTokens', dispositivo.id);
  const url = dispositivo.updateTime
    ? `${base}?currentDocument.updateTime=${encodeURIComponent(dispositivo.updateTime)}`
    : `${base}?currentDocument.exists=true`;
  try {
    const resp = await fetchConCuenta(env, url, { method: 'DELETE' }, deps, 'firestore_borrar_dispositivo');
    return resp.ok;
  } catch {
    return false;
  }
}
