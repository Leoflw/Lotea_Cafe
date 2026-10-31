// Envío por FCM HTTP v1 y clasificación de sus errores.
// Referencias:
//   https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send
//   https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode
//
// El contenido es SIEMPRE genérico y lo decide el Worker: nunca llega texto del
// cliente ni se incluye contenido del chat o de la cotización (la pantalla de
// bloqueo no debe revelar nada privado). El payload `data` solo lleva dos
// valores opacos para abrir la pantalla correcta: `ruta` e `id`.

import { diagHttpConCuerpo, sanear } from './diagnostico.js';
import { UpstreamError } from './errores.js';
import { fetchConCuenta } from './google-auth.js';

export const CANAL_ANDROID_POR_DEFECTO = 'lotea_mensajes_cotizaciones';

const TEXTOS = {
  chat: { titulo: 'Nuevo mensaje', cuerpo: 'Tienes un nuevo mensaje en Lotea Café' },
  cotizacion: { titulo: 'Novedades en una cotización', cuerpo: 'Tienes novedades en una cotización de Lotea Café' },
};

/** Mensaje FCM v1 para un dispositivo. [ruta] es 'chat' o 'cotizacion'. */
export function construirMensaje({ token, ruta, id, canal }) {
  const t = TEXTOS[ruta];
  return {
    message: {
      token,
      notification: { title: t.titulo, body: t.cuerpo },
      data: { ruta, id },
      android: {
        priority: 'HIGH',
        ttl: '86400s',
        notification: { channel_id: canal || CANAL_ANDROID_POR_DEFECTO, tag: `${ruta}_${id}` },
      },
    },
  };
}

const TRANSITORIOS_HTTP = new Set([429, 500, 502, 503, 504]);
const TRANSITORIOS_ESTADO = new Set(['UNAVAILABLE', 'INTERNAL', 'QUOTA_EXCEEDED', 'DEADLINE_EXCEEDED', 'RESOURCE_EXHAUSTED']);

/**
 * Clasifica la respuesta de FCM:
 *  - 'tokenInvalido'  Google CONFIRMA que el token no existe (UNREGISTERED) o
 *                     que el token está mal formado (INVALID_ARGUMENT sobre
 *                     el campo message.token). Único caso en que se borra.
 *  - 'transitorio'    429, 5xx, UNAVAILABLE…: se puede reintentar; NO se borra nada.
 *  - 'configuracion'  credenciales, permisos, proyecto o carga incorrectos
 *                     (401/403, SENDER_ID_MISMATCH, 404 sin UNREGISTERED,
 *                     INVALID_ARGUMENT en otro campo…); NO se borra nada.
 *
 * Un 404 genérico (p. ej. proyecto mal escrito) NO es «token inexistente»:
 * solo el código FCM UNREGISTERED lo es. Así una configuración equivocada no
 * puede vaciar los tokens de los usuarios.
 */
export function clasificarError(status, cuerpo) {
  const error = cuerpo?.error ?? {};
  const detalles = Array.isArray(error.details) ? error.details : [];
  const codigoFcm = detalles.find((d) => typeof d?.errorCode === 'string')?.errorCode ?? null;

  if (codigoFcm === 'UNREGISTERED') return 'tokenInvalido';
  if (codigoFcm === 'INVALID_ARGUMENT' || error.status === 'INVALID_ARGUMENT') {
    const violaciones = detalles.flatMap((d) => (Array.isArray(d?.fieldViolations) ? d.fieldViolations : []));
    if (violaciones.some((v) => typeof v?.field === 'string' && /(^|\.)token$/.test(v.field))) return 'tokenInvalido';
    return 'configuracion';
  }
  if (TRANSITORIOS_HTTP.has(status) || TRANSITORIOS_ESTADO.has(error.status) || TRANSITORIOS_ESTADO.has(codigoFcm)) {
    return 'transitorio';
  }
  return 'configuracion';
}

/**
 * Envía a UN dispositivo y devuelve { resultado, diag }. [resultado] es 'ok' |
 * 'tokenInvalido' | 'transitorio' | 'configuracion'. [diag] (solo si no fue
 * 'ok') es un diagnóstico seguro: etapa, servicio, causa, código HTTP y códigos
 * de Google de la lista permitida. No incluye el token ni el cuerpo de Google.
 */
export async function enviarDetallado(env, proyecto, mensaje, deps) {
  let resp;
  try {
    resp = await fetchConCuenta(
      env,
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(proyecto)}/messages:send`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(mensaje) },
      deps,
      'fcm_enviar',
    );
  } catch (e) {
    // Red caída o OAuth temporalmente no disponible: el diag (si lo hay) dice cuál.
    if (e instanceof UpstreamError) return { resultado: 'transitorio', diag: sanear(e.diag ?? { etapa: 'fcm_enviar', servicio: 'fcm', causa: 'red' }) };
    throw e; // ConfigError (credenciales) sube a index.js
  }
  if (resp.ok) return { resultado: 'ok', diag: null };
  let cuerpo = null;
  try {
    cuerpo = await resp.json();
  } catch {
    /* cuerpo no JSON: se clasifica solo por el código HTTP */
  }
  return { resultado: clasificarError(resp.status, cuerpo), diag: sanear(diagHttpConCuerpo('fcm_enviar', resp.status, cuerpo)) };
}

/** Envía a UN dispositivo. Devuelve 'ok' | 'tokenInvalido' | 'transitorio' | 'configuracion'. */
export async function enviar(env, proyecto, mensaje, deps) {
  return (await enviarDetallado(env, proyecto, mensaje, deps)).resultado;
}
