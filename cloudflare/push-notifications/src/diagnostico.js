// Diagnóstico estructurado y SEGURO de los fallos del Worker.
//
// Objetivo: que `npx wrangler tail` diga en qué etapa falló una petición y qué
// código HTTP devolvió Google, sin registrar nada privado.
//
// Regla de oro: en el registro solo entran VALORES DE UN CONJUNTO CERRADO
// (etapas, servicios, causas, motivos, códigos de Google de una lista permitida)
// y números HTTP. Jamás texto libre de Google (`message`, `error_description`,
// `details` completos), ni identificadores, tokens, credenciales o chat. Un
// código de Google que no esté en la lista se registra como «otro».

import { ConfigError, UpstreamError } from './errores.js';

export const ETAPAS = new Set([
  'verificar_id_token', // claves públicas de Firebase (JWKS) para validar el ID token
  'firestore_leer_evento', // lectura con el ID token del usuario (conexión, mensaje, cotización, evento)
  'oauth_cuenta_servicio', // lectura/importación local del secreto (sin red)
  'oauth_token', // canje del JWT por un access token en oauth2.googleapis.com
  'firestore_listar_dispositivos',
  'firestore_dedupe', // marcador de etapa en index.js (el detalle va en las siguientes)
  'firestore_dedupe_crear',
  'firestore_dedupe_leer',
  'firestore_dedupe_relevo',
  'firestore_dedupe_marcar',
  'firestore_dedupe_liberar',
  'fcm_enviar',
  'firestore_borrar_dispositivo',
  'firestore_dedupe_cierre', // marcador de etapa en index.js
  'diagnostico_salida', // GET /diagnostico: salida a Internet sin credenciales
  'diagnostico_firestore', // GET /diagnostico: lectura autenticada de un documento fijo
  'validar_peticion', // marcador de etapa en index.js (antes de llamar a Google)
]);

const SERVICIOS = new Set(['oauth', 'firestore', 'fcm', 'firebase_auth']);
const CAUSAS = new Set(['red', 'http', 'respuesta_invalida']);
const OBJETOS = new Set(['conexion', 'mensaje', 'cotizacion', 'evento']);
const MOTIVOS = new Set([
  'secreto_ausente',
  'json_invalido',
  'no_es_objeto',
  'sin_client_email',
  'sin_clave_privada',
  'proyecto_distinto',
  'clave_ilegible',
  'oauth_rechazado',
]);

// ---- Listas permitidas de códigos de Google ----
// google.rpc.Code / error.status (Firestore, FCM, APIs de Google).
export const GOOGLE_STATUS = new Set([
  'INVALID_ARGUMENT', 'FAILED_PRECONDITION', 'OUT_OF_RANGE', 'UNAUTHENTICATED', 'PERMISSION_DENIED',
  'NOT_FOUND', 'ABORTED', 'ALREADY_EXISTS', 'RESOURCE_EXHAUSTED', 'CANCELLED', 'DATA_LOSS',
  'UNKNOWN', 'INTERNAL', 'UNIMPLEMENTED', 'UNAVAILABLE', 'DEADLINE_EXCEEDED',
]);
// google.rpc.ErrorInfo.reason (el «porqué» de un 403/401 en APIs de Google).
export const GOOGLE_RAZON = new Set([
  'SERVICE_DISABLED', 'ACCESS_TOKEN_SCOPE_INSUFFICIENT', 'ACCESS_TOKEN_EXPIRED', 'IAM_PERMISSION_DENIED',
  'BILLING_DISABLED', 'RATE_LIMIT_EXCEEDED', 'CONSUMER_INVALID', 'API_KEY_INVALID', 'CREDENTIALS_MISSING',
  'USER_PROJECT_DENIED',
]);
// FcmError.errorCode (https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode).
export const FCM_CODIGO = new Set([
  'UNSPECIFIED_ERROR', 'INVALID_ARGUMENT', 'UNREGISTERED', 'SENDER_ID_MISMATCH', 'QUOTA_EXCEEDED',
  'UNAVAILABLE', 'INTERNAL', 'THIRD_PARTY_AUTH_ERROR',
]);
// Campo `error` de OAuth 2.0 (RFC 6749 §5.2) en oauth2.googleapis.com/token.
export const OAUTH_ERROR = new Set([
  'invalid_request', 'invalid_client', 'invalid_grant', 'unauthorized_client', 'unsupported_grant_type',
  'invalid_scope', 'access_denied',
]);

/** El valor si está en la lista; 'otro' si hay un valor pero no está permitido; undefined si no hay. */
function permitido(valor, lista) {
  if (typeof valor !== 'string' || valor.length === 0) return undefined;
  return lista.has(valor) ? valor : 'otro';
}

/**
 * Entre varios valores (p. ej. los `details` de un error) elige el PRIMERO que
 * esté en la lista; si hay valores pero ninguno permitido → 'otro'; si no hay → undefined.
 * Así un detalle desconocido no oculta uno válido que venga después.
 */
function primerPermitido(valores, lista) {
  const textos = valores.filter((v) => typeof v === 'string' && v.length > 0);
  if (textos.length === 0) return undefined;
  return textos.find((v) => lista.has(v)) ?? 'otro';
}

const MAX_CUERPO_ERROR = 16 * 1024;

/** Lee el cuerpo JSON de una respuesta de error sin lanzar. Devuelve null si no se puede. */
export async function leerCuerpoError(resp) {
  try {
    const crudo = await resp.text();
    if (crudo.length > MAX_CUERPO_ERROR) return null;
    return JSON.parse(crudo);
  } catch {
    return null;
  }
}

/**
 * Extrae SOLO códigos de la lista permitida de un cuerpo de error de Google
 * (Firestore/FCM: {error:{status,details:[{reason}|{errorCode}]}}; OAuth:
 * {error:'invalid_grant', error_description:'…'}). El texto libre se descarta.
 */
export function codigosDeGoogle(cuerpo) {
  const salida = {};
  if (cuerpo === null || typeof cuerpo !== 'object') return salida;
  const err = cuerpo.error;
  if (typeof err === 'string') {
    const o = permitido(err, OAUTH_ERROR);
    if (o) salida.oauthError = o;
    return salida;
  }
  if (err === null || typeof err !== 'object') return salida;
  const status = permitido(err.status, GOOGLE_STATUS);
  if (status) salida.googleStatus = status;
  const detalles = Array.isArray(err.details) ? err.details : [];
  const razon = primerPermitido(detalles.map((d) => d?.reason), GOOGLE_RAZON);
  if (razon) salida.googleRazon = razon;
  const codigoFcm = primerPermitido(detalles.map((d) => d?.errorCode), FCM_CODIGO);
  if (codigoFcm) salida.fcmCodigo = codigoFcm;
  return salida;
}

/** Servicio de Google al que pertenece una etapa. */
export function servicioDeEtapa(etapa) {
  if (etapa.startsWith('oauth_')) return 'oauth';
  if (etapa.startsWith('fcm_')) return 'fcm';
  if (etapa === 'verificar_id_token') return 'firebase_auth';
  return 'firestore';
}

// ---- Excepciones de transporte (fetch lanzó en vez de devolver una respuesta) ----
// Nombre de CLASE del error (nunca el mensaje).
const NOMBRES_CLASE = new Set(['Error', 'TypeError', 'RangeError', 'SyntaxError', 'ReferenceError', 'DOMException', 'AggregateError']);
// Códigos técnicos de causa: conjunto CERRADO. Se pueden deducir de e.name, de e.code / e.cause.code
// (códigos de sistema y de undici, tal cual) o del texto del mensaje, que SOLO se usa como entrada
// de la clasificación (se compara con patrones) y jamás se copia al registro.
export const CODIGOS_CAUSA = new Set([
  'invocacion_ilegal', // «Illegal invocation»: fetch llamado con un `this` incorrecto (Workers)
  'conexion_perdida', // «Network connection lost» (Workers)
  'limite_subpeticiones', // «Too many subrequests» (Workers)
  'cuerpo_ya_usado', // body ya consumido o desconectado
  'timeout',
  'abortado',
  'sin_clasificar',
  'ECONNRESET', 'ECONNREFUSED', 'ENOTFOUND', 'ETIMEDOUT', 'EAI_AGAIN', 'EPIPE',
  'UND_ERR_CONNECT_TIMEOUT', 'UND_ERR_SOCKET', 'UND_ERR_HEADERS_TIMEOUT', 'UND_ERR_BODY_TIMEOUT',
  'ERR_TLS_CERT_ALTNAME_INVALID', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'CERT_HAS_EXPIRED',
]);
const PATRONES_MENSAJE = [
  [/illegal invocation|incorrect `?this`? reference/i, 'invocacion_ilegal'],
  [/network connection lost/i, 'conexion_perdida'],
  [/too many subrequests/i, 'limite_subpeticiones'],
  [/body (has already been used|is unusable|stream)|disturbed|already been (used|read)/i, 'cuerpo_ya_usado'],
  [/timed? ?out|timeout/i, 'timeout'],
  [/abort/i, 'abortado'],
];
const POR_NOMBRE = { AbortError: 'abortado', TimeoutError: 'timeout' };

/**
 * Clasifica una excepción SIN revelar su contenido. Devuelve { errorNombre, errorCodigo }, ambos
 * valores de conjuntos cerrados ('otro' si la clase no es conocida; 'sin_clasificar' si no encaja).
 */
export function clasificarExcepcion(e) {
  const clase = e?.constructor?.name;
  const errorNombre = typeof clase === 'string' && NOMBRES_CLASE.has(clase) ? clase : 'otro';
  let errorCodigo;
  for (const candidato of [e?.cause?.code, e?.code]) {
    if (typeof candidato === 'string' && CODIGOS_CAUSA.has(candidato)) {
      errorCodigo = candidato;
      break;
    }
  }
  if (!errorCodigo && typeof e?.name === 'string' && Object.hasOwn(POR_NOMBRE, e.name)) errorCodigo = POR_NOMBRE[e.name];
  if (!errorCodigo) {
    const mensaje = typeof e?.message === 'string' ? e.message.slice(0, 500) : '';
    errorCodigo = PATRONES_MENSAJE.find(([patron]) => patron.test(mensaje))?.[1] ?? 'sin_clasificar';
  }
  return { errorNombre, errorCodigo };
}

/** Diagnóstico de un fallo de red (fetch lanzó una excepción; el mensaje se descarta). */
export function diagRed(etapa, extra = {}) {
  return { etapa, servicio: servicioDeEtapa(etapa), causa: 'red', ...extra };
}

/** Igual que diagRed, añadiendo la clasificación segura de la excepción capturada. */
export function diagExcepcion(etapa, e, extra = {}) {
  return diagRed(etapa, { ...clasificarExcepcion(e), ...extra });
}

/** Diagnóstico de una respuesta HTTP no satisfactoria. Lee el cuerpo SOLO para sacar códigos permitidos. */
export async function diagHttp(etapa, resp, extra = {}) {
  const cuerpo = await leerCuerpoError(resp);
  return { etapa, servicio: servicioDeEtapa(etapa), causa: 'http', http: resp.status, ...codigosDeGoogle(cuerpo), ...extra };
}

/** Diagnóstico cuando el cuerpo del error YA se leyó (p. ej. en FCM). */
export function diagHttpConCuerpo(etapa, status, cuerpo, extra = {}) {
  return { etapa, servicio: servicioDeEtapa(etapa), causa: 'http', http: status, ...codigosDeGoogle(cuerpo), ...extra };
}

/**
 * Reduce CUALQUIER objeto a los campos y valores permitidos. Es la última
 * barrera antes de escribir en el registro: aunque un diag llegara con texto
 * libre, aquí se descarta.
 */
export function sanear(diag) {
  const d = diag && typeof diag === 'object' ? diag : {};
  const salida = {};
  const puesto = (clave, valor) => {
    if (valor !== undefined) salida[clave] = valor;
  };
  puesto('etapa', typeof d.etapa === 'string' ? (ETAPAS.has(d.etapa) ? d.etapa : 'otra') : undefined);
  puesto('operacion', typeof d.operacion === 'string' ? (ETAPAS.has(d.operacion) ? d.operacion : 'otra') : undefined);
  puesto('servicio', typeof d.servicio === 'string' ? (SERVICIOS.has(d.servicio) ? d.servicio : 'otro') : undefined);
  puesto('causa', typeof d.causa === 'string' ? (CAUSAS.has(d.causa) ? d.causa : 'otra') : undefined);
  puesto('objeto', typeof d.objeto === 'string' ? (OBJETOS.has(d.objeto) ? d.objeto : 'otro') : undefined);
  puesto('motivo', typeof d.motivo === 'string' ? (MOTIVOS.has(d.motivo) ? d.motivo : 'otro') : undefined);
  puesto('errorNombre', typeof d.errorNombre === 'string' ? (NOMBRES_CLASE.has(d.errorNombre) ? d.errorNombre : 'otro') : undefined);
  puesto('errorCodigo', permitido(d.errorCodigo, CODIGOS_CAUSA));
  puesto('http', Number.isInteger(d.http) && d.http >= 100 && d.http <= 599 ? d.http : undefined);
  puesto('googleStatus', permitido(d.googleStatus, GOOGLE_STATUS));
  puesto('googleRazon', permitido(d.googleRazon, GOOGLE_RAZON));
  puesto('fcmCodigo', permitido(d.fcmCodigo, FCM_CODIGO));
  puesto('oauthError', permitido(d.oauthError, OAUTH_ERROR));
  return salida;
}

const NOMBRES_ERROR = new Set(['Error', 'TypeError', 'RangeError', 'SyntaxError', 'ReferenceError', 'DOMException', 'OperationError', 'DataError']);

/** Nombre de la clase de un error inesperado, solo si es uno conocido (nunca el mensaje). */
export const nombreSeguro = (e) => (typeof e?.name === 'string' && NOMBRES_ERROR.has(e.name) ? e.name : 'otro');

/** Copia el error añadiéndole la operación que necesitaba el token. Conserva clase y mensaje. */
export function conOperacion(e, operacion) {
  if (!(e instanceof UpstreamError || e instanceof ConfigError) || !e.diag || e.diag.operacion) return e;
  const Clase = e instanceof UpstreamError ? UpstreamError : ConfigError;
  return new Clase(e.message, { ...e.diag, operacion });
}
