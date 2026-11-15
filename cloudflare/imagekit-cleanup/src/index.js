// Cloudflare Worker de limpieza de imágenes de ImageKit — Lotea Café.
//
// Dos entradas:
//  - POST /  (la app, tras guardar un lote o perfil): con el ID token de Firebase
//    procesa la cola DEL PROPIO USUARIO. El cuerpo se ignora: la app no envía
//    ningún fileId; los ids salen de la cola y se validan uno a uno.
//  - scheduled (cron): reintenta la cola de todos los usuarios (recuperación tras
//    errores temporales o interrupciones aunque la app no se vuelva a abrir) y revisa las
//    fotos «retenida» por el historial.
//
// Plan gratuito: máx. 50 subpeticiones por invocación; por eso se limita lo que se procesa
// por llamada. Si quedan más, se informa en `restantes` y se completan en la siguiente
// llamada o en el cron.

import { ErrorConfig } from './errores.js';
import { AuthError, verifyIdToken } from './firebase.js';
import { esProcesable, procesarSolicitud } from './cleanup.js';
import { listarColaDeUsuario, listarColaGlobal } from './firestore.js';
import { COLECCION as LOTES, procesarBorradoLote } from './lotes.js';

// Presupuesto de subpeticiones (plan gratuito: 50 por invocación): una eliminación de lote usa
// ≈11 y una foto ≈8 (con las 4 comprobaciones de uso), más ≈10 de listados y autenticación.
export const MAX_LOTES_POR_EJECUCION = 1;
export const MAX_POR_EJECUCION = 3; // fotos
const LIMITE = { max: 20, ventanaMs: 10 * 60 * 1000 }; // 20 llamadas / 10 min / usuario

const usos = new Map();
export function resetLimitador() {
  usos.clear();
}
function excedeLimite(uid, nowMs) {
  const recientes = (usos.get(uid) || []).filter((t) => nowMs - t < LIMITE.ventanaMs);
  if (recientes.length >= LIMITE.max) {
    usos.set(uid, recientes);
    return true;
  }
  recientes.push(nowMs);
  usos.set(uid, recientes);
  if (usos.size > 5000) usos.clear();
  return false;
}

const json = (estado, cuerpo) =>
  new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
const error = (estado, mensaje) => json(estado, { error: mensaje });

function configurado(env) {
  return Boolean(env.FIREBASE_PROJECT_ID && env.IMAGEKIT_PRIVATE_KEY && env.CLEANUP_SERVICE_ACCOUNT_JSON);
}

const RESUMEN_VACIO = () => ({ procesadas: 0, completadas: 0, enUso: 0, retenidas: 0, rechazadas: 0, reintentos: 0, fallidas: 0, omitidas: 0, lotes: 0 });
const CLAVE_RESUMEN = { completado: 'completadas', enUso: 'enUso', retenida: 'retenidas', rechazado: 'rechazadas', reintentar: 'reintentos', fallido: 'fallidas', omitido: 'omitidas' };

/**
 * Procesa primero las eliminaciones de lote (limpian el historial y liberan fotos) y luego
 * las solicitudes de foto, respetando el presupuesto de subpeticiones. Devuelve el resumen.
 */
async function procesarLote(env, { fotos, lotes = [] }, deps) {
  const resumen = RESUMEN_VACIO();
  const lotesPend = lotes.filter((d) => esProcesable(d, deps.nowMs));
  for (const doc of lotesPend.slice(0, MAX_LOTES_POR_EJECUCION)) {
    const r = await procesarBorradoLote(env, doc, deps);
    resumen.procesadas += 1;
    resumen[CLAVE_RESUMEN[r]] += 1;
    if (r === 'completado') resumen.lotes += 1;
  }
  const candidatas = fotos.filter((d) => esProcesable(d, deps.nowMs));
  for (const doc of candidatas.slice(0, MAX_POR_EJECUCION)) {
    const r = await procesarSolicitud(env, doc, deps);
    resumen.procesadas += 1;
    resumen[CLAVE_RESUMEN[r]] += 1;
  }
  resumen.restantes = Math.max(0, lotesPend.length - MAX_LOTES_POR_EJECUCION) + Math.max(0, candidatas.length - MAX_POR_EJECUCION);
  return resumen;
}

export async function handle(request, env, deps = {}) {
  const d = { fetchFn: deps.fetch ?? fetch, nowMs: deps.nowMs ?? Date.now() };
  const url = new URL(request.url);

  if (url.protocol !== 'https:' && env.ALLOW_HTTP !== 'true') return error(400, 'Se requiere HTTPS.');
  if (request.method !== 'POST') return error(405, 'Método no permitido.');
  if (url.pathname !== '/') return error(404, 'No encontrado.');
  if (!configurado(env)) return error(500, 'El Worker no está configurado.');

  const m = /^Bearer (.+)$/.exec(request.headers.get('Authorization') || '');
  if (!m) return error(401, 'Falta el token de sesión.');
  let payload;
  try {
    payload = await verifyIdToken(m[1].trim(), { projectId: env.FIREBASE_PROJECT_ID, fetchFn: d.fetchFn, nowMs: d.nowMs });
  } catch (e) {
    if (e instanceof AuthError) return error(401, 'Sesión no válida. Inicia sesión de nuevo.');
    return error(503, 'No se pudo validar la sesión. Inténtalo de nuevo.');
  }
  const uid = payload.sub; // el UID sale del token verificado, nunca del cuerpo

  if (excedeLimite(uid, d.nowMs)) return error(429, 'Demasiadas llamadas seguidas. Espera unos minutos.');

  try {
    const fotos = await listarColaDeUsuario(env, uid, d);
    const lotes = await listarColaDeUsuario(env, uid, d, LOTES);
    return json(200, await procesarLote(env, { fotos, lotes }, d));
  } catch (e) {
    if (e instanceof ErrorConfig) return error(500, 'El Worker no está configurado correctamente.');
    return error(503, 'No se pudo procesar la cola ahora. Se reintentará automáticamente.');
  }
}

/** Cron: reintenta pendientes, con error temporal y reclamadas por un proceso que murió. */
export async function barrido(env, deps = {}) {
  const d = { fetchFn: deps.fetch ?? fetch, nowMs: deps.nowMs ?? Date.now() };
  if (!configurado(env)) return RESUMEN_VACIO();
  const fotos = [];
  const lotes = [];
  for (const estado of ['pendiente', 'errorTemporal', 'procesando']) {
    lotes.push(...(await listarColaGlobal(env, estado, 10, d, LOTES)));
  }
  for (const estado of ['pendiente', 'errorTemporal', 'procesando', 'retenida']) {
    fotos.push(...(await listarColaGlobal(env, estado, 10, d)));
  }
  return procesarLote(env, { fotos, lotes }, d);
}

export default {
  fetch(request, env) {
    return handle(request, env);
  },
  scheduled(_evento, env, ctx) {
    ctx.waitUntil(barrido(env).catch(() => {}));
  },
};
