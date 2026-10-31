// Autenticación del Worker ante Google con una cuenta de servicio.
//
// Flujo (https://developers.google.com/identity/protocols/oauth2/service-account#httprest):
//   1. Se firma un JWT RS256 con la clave privada de la cuenta de servicio.
//   2. Se canjea en https://oauth2.googleapis.com/token por un access token (~1 h).
//   3. El access token se usa para Firestore (tokens de dispositivos y
//      deduplicación) y para FCM HTTP v1.
//
// La cuenta de servicio llega SOLO como secreto `FCM_SERVICE_ACCOUNT_JSON`
// (nunca en el código ni en wrangler.toml). Este módulo no registra ni
// devuelve su contenido en ningún mensaje de error.
//
// Coste de CPU (plan gratuito de Workers: 10 ms por petición): lo caro es
// importar la clave PKCS#8 y firmar con RSA-2048. Por eso la CryptoKey y el
// access token se guardan en memoria del isolate y se reutilizan hasta 5
// minutos antes de caducar. Un isolate nuevo («arranque en frío») paga una
// firma; las siguientes peticiones del mismo isolate no. Ver
// scripts/medir-cpu.mjs y README.md (sección «Límite de CPU»).
//
// No se usa la Cache API para compartir el token entre isolates: no funciona
// en dominios *.workers.dev.

import { clasificarExcepcion, conOperacion, diagExcepcion, diagHttp } from './diagnostico.js';
import { ConfigError, UpstreamError } from './errores.js';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPES = [
  'https://www.googleapis.com/auth/firebase.messaging',
  'https://www.googleapis.com/auth/datastore',
].join(' ');
const MARGEN_SEGUNDOS = 300; // se renueva 5 min antes de que caduque

let cache = { huella: null, clave: null, token: null, expiraMs: 0, pendiente: null };

/** Solo para pruebas. */
export function resetAuthCache() {
  cache = { huella: null, clave: null, token: null, expiraMs: 0, pendiente: null };
}

/** Solo para pruebas y para forzar la renovación tras un 401. */
export function invalidarAccessToken() {
  cache.token = null;
  cache.expiraMs = 0;
}

const aBase64Url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const textoABase64Url = (texto) => aBase64Url(new TextEncoder().encode(texto));

function base64ABytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Lee y valida el secreto. Lanza [ConfigError] sin incluir su contenido. */
export function leerCuentaDeServicio(crudo, projectId) {
  let sa;
  const cfg = (mensaje, motivo) => new ConfigError(mensaje, { etapa: 'oauth_cuenta_servicio', servicio: 'oauth', motivo });
  try {
    sa = JSON.parse(crudo);
  } catch {
    throw cfg('FCM_SERVICE_ACCOUNT_JSON no es un JSON válido.', 'json_invalido');
  }
  if (sa === null || typeof sa !== 'object') throw cfg('FCM_SERVICE_ACCOUNT_JSON no es un objeto.', 'no_es_objeto');
  const { client_email: clientEmail, private_key: clavePem, project_id: proyecto } = sa;
  if (typeof clientEmail !== 'string' || !clientEmail.includes('@')) throw cfg('La cuenta de servicio no tiene client_email.', 'sin_client_email');
  if (typeof clavePem !== 'string' || !clavePem.includes('BEGIN PRIVATE KEY')) throw cfg('La cuenta de servicio no tiene una clave privada PKCS#8.', 'sin_clave_privada');
  if (proyecto !== projectId) throw cfg('La cuenta de servicio pertenece a otro proyecto de Firebase.', 'proyecto_distinto');
  return { clientEmail, clavePem };
}

async function importarClave(clavePem) {
  const b64 = clavePem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  try {
    return await crypto.subtle.importKey(
      'pkcs8',
      base64ABytes(b64),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
  } catch {
    throw new ConfigError('No se pudo leer la clave privada de la cuenta de servicio.', { etapa: 'oauth_cuenta_servicio', servicio: 'oauth', motivo: 'clave_ilegible' });
  }
}

async function firmarJwt({ clientEmail }, clave, ahoraS) {
  const cabecera = textoABase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const cuerpo = textoABase64Url(
    JSON.stringify({ iss: clientEmail, scope: SCOPES, aud: TOKEN_URL, iat: ahoraS, exp: ahoraS + 3600 }),
  );
  const firma = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', clave, new TextEncoder().encode(`${cabecera}.${cuerpo}`));
  return `${cabecera}.${cuerpo}.${aBase64Url(firma)}`;
}

async function pedirAccessToken(sa, huella, fetchFn, nowMs) {
  if (cache.huella !== huella || !cache.clave) {
    cache.clave = await importarClave(sa.clavePem);
    cache.huella = huella;
  }
  const assertion = await firmarJwt(sa, cache.clave, Math.floor(nowMs / 1000));
  let resp;
  try {
    resp = await fetchFn(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
    });
  } catch (e) {
    throw new UpstreamError('No se pudo contactar con el servicio de autenticación de Google.', diagExcepcion('oauth_token', e));
  }
  if (resp.status >= 500 || resp.status === 429) throw new UpstreamError(`OAuth respondió ${resp.status}.`, await diagHttp('oauth_token', resp));
  if (!resp.ok) throw new ConfigError(`Google rechazó las credenciales de la cuenta de servicio (${resp.status}).`, await diagHttp('oauth_token', resp, { motivo: 'oauth_rechazado' }));
  const datos = await resp.json();
  if (typeof datos.access_token !== 'string') throw new UpstreamError('Respuesta OAuth sin access_token.', { etapa: 'oauth_token', servicio: 'oauth', causa: 'respuesta_invalida' });
  const vida = Number.isFinite(datos.expires_in) ? datos.expires_in : 3600;
  cache.token = datos.access_token;
  cache.expiraMs = nowMs + Math.max(0, vida - MARGEN_SEGUNDOS) * 1000;
  return cache.token;
}

/** Access token vigente (de caché si se puede). Peticiones simultáneas comparten una sola renovación. */
export async function obtenerAccessToken(env, { fetchFn, nowMs }) {
  const crudo = env.FCM_SERVICE_ACCOUNT_JSON;
  if (typeof crudo !== 'string' || crudo.length === 0) throw new ConfigError('Falta el secreto FCM_SERVICE_ACCOUNT_JSON.', { etapa: 'oauth_cuenta_servicio', servicio: 'oauth', motivo: 'secreto_ausente' });
  if (cache.token && cache.huella === crudo && nowMs < cache.expiraMs) return cache.token;
  if (cache.pendiente && cache.huella === crudo) return cache.pendiente;

  const sa = leerCuentaDeServicio(crudo, env.FIREBASE_PROJECT_ID);
  const promesa = pedirAccessToken(sa, crudo, fetchFn, nowMs).finally(() => {
    if (cache.pendiente === promesa) cache.pendiente = null;
  });
  cache.huella = crudo;
  cache.pendiente = promesa;
  return promesa;
}

/**
 * fetch autenticado con la cuenta de servicio. Si Google responde 401 (token
 * revocado o caducado antes de tiempo) renueva el token UNA vez y reintenta.
 * Los errores de red se convierten en [UpstreamError].
 *
 * [operacion] (opcional) es la etapa que pidió la llamada; se añade al
 * diagnóstico para distinguir, p. ej., un fallo de OAuth que ocurrió al listar
 * dispositivos de uno que ocurrió al enviar a FCM.
 */
export async function fetchConCuenta(env, url, init, deps, operacion) {
  // IMPORTANTE (Cloudflare Workers): `fetch` debe llamarse SIN objeto receptor. Llamarlo como
  // `deps.fetchFn(...)` le pasa `this = deps` y el runtime lanza «TypeError: Illegal invocation:
  // function called with incorrect `this` reference». Por eso se extrae a una constante local y
  // se invoca como función simple (igual que ya hacían OAuth y las lecturas como usuario).
  const { fetchFn } = deps;
  const intentar = async () => {
    let token;
    try {
      token = await obtenerAccessToken(env, deps);
    } catch (e) {
      throw operacion ? conOperacion(e, operacion) : e;
    }
    try {
      return await fetchFn(url, { ...init, headers: { ...(init.headers || {}), Authorization: `Bearer ${token}` } });
    } catch (e) {
      // Excepción de TRANSPORTE (no hubo respuesta HTTP): se registra la clase y un código técnico
      // de una lista cerrada; nunca e.message ni la cabecera Authorization.
      throw new UpstreamError('Fallo de red al contactar con Google.', operacion ? diagExcepcion(operacion, e) : { causa: 'red', ...clasificarExcepcion(e) });
    }
  };
  let resp = await intentar();
  if (resp.status === 401) {
    invalidarAccessToken();
    resp = await intentar();
  }
  return resp;
}
