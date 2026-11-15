// Autenticación del Worker ante Google con una cuenta de servicio PROPIA de
// este Worker (distinta de la de notificaciones push), con un único alcance:
// Firestore (`datastore`). Referencia:
// https://developers.google.com/identity/protocols/oauth2/service-account#httprest
//
// El access token (~1 h) y la clave importada se guardan en memoria del isolate.
// La cuenta llega SOLO como secreto CLEANUP_SERVICE_ACCOUNT_JSON y nunca se
// registra ni se devuelve en un error.

import { ErrorConfig, ErrorTemporal } from './errores.js';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/datastore';
const MARGEN_SEGUNDOS = 300;

let cache = { huella: null, clave: null, token: null, expiraMs: 0 };

/** Solo para pruebas. */
export function resetAuthCache() {
  cache = { huella: null, clave: null, token: null, expiraMs: 0 };
}

const aBase64Url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const textoABase64Url = (t) => aBase64Url(new TextEncoder().encode(t));

function base64ABytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function leerCuentaDeServicio(crudo, projectId) {
  let sa;
  try {
    sa = JSON.parse(crudo);
  } catch {
    throw new ErrorConfig('cuenta_json_invalido');
  }
  if (sa === null || typeof sa !== 'object') throw new ErrorConfig('cuenta_no_objeto');
  if (typeof sa.client_email !== 'string' || !sa.client_email.includes('@')) throw new ErrorConfig('cuenta_sin_email');
  if (typeof sa.private_key !== 'string' || !sa.private_key.includes('BEGIN PRIVATE KEY')) throw new ErrorConfig('cuenta_sin_clave');
  if (sa.project_id !== projectId) throw new ErrorConfig('cuenta_otro_proyecto');
  return { clientEmail: sa.client_email, clavePem: sa.private_key };
}

async function importarClave(clavePem) {
  const b64 = clavePem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  try {
    return await crypto.subtle.importKey('pkcs8', base64ABytes(b64), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  } catch {
    throw new ErrorConfig('cuenta_clave_ilegible');
  }
}

async function pedirToken(sa, huella, fetchFn, nowMs) {
  if (cache.huella !== huella || !cache.clave) {
    cache.clave = await importarClave(sa.clavePem);
    cache.huella = huella;
  }
  const ahoraS = Math.floor(nowMs / 1000);
  const cabecera = textoABase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const cuerpo = textoABase64Url(JSON.stringify({ iss: sa.clientEmail, scope: SCOPE, aud: TOKEN_URL, iat: ahoraS, exp: ahoraS + 3600 }));
  const firma = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cache.clave, new TextEncoder().encode(`${cabecera}.${cuerpo}`));
  const assertion = `${cabecera}.${cuerpo}.${aBase64Url(firma)}`;

  let resp;
  try {
    resp = await fetchFn(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
    });
  } catch {
    throw new ErrorTemporal('oauth_red');
  }
  if (resp.status >= 500 || resp.status === 429) throw new ErrorTemporal('oauth_5xx');
  if (!resp.ok) throw new ErrorConfig('oauth_rechazado');
  const datos = await resp.json();
  if (typeof datos.access_token !== 'string') throw new ErrorTemporal('oauth_respuesta');
  const vida = Number.isFinite(datos.expires_in) ? datos.expires_in : 3600;
  cache.token = datos.access_token;
  cache.expiraMs = nowMs + Math.max(0, vida - MARGEN_SEGUNDOS) * 1000;
  return cache.token;
}

export async function obtenerAccessToken(env, { fetchFn, nowMs }) {
  const crudo = env.CLEANUP_SERVICE_ACCOUNT_JSON;
  if (typeof crudo !== 'string' || crudo.length === 0) throw new ErrorConfig('cuenta_ausente');
  if (cache.token && cache.huella === crudo && nowMs < cache.expiraMs) return cache.token;
  return pedirToken(leerCuentaDeServicio(crudo, env.FIREBASE_PROJECT_ID), crudo, fetchFn, nowMs);
}

/** fetch autenticado con la cuenta de servicio; ante un 401 renueva el token una vez. */
export async function fetchConCuenta(env, url, init, deps) {
  const { fetchFn } = deps; // se invoca sin receptor (Workers lanza «Illegal invocation» si no)
  const intentar = async () => {
    const token = await obtenerAccessToken(env, deps);
    try {
      return await fetchFn(url, { ...init, headers: { ...(init.headers || {}), Authorization: `Bearer ${token}` } });
    } catch {
      throw new ErrorTemporal('firestore_red');
    }
  };
  let resp = await intentar();
  if (resp.status === 401) {
    cache.token = null;
    cache.expiraMs = 0;
    resp = await intentar();
  }
  return resp;
}
