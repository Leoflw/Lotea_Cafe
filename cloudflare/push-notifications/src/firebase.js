// Validación criptográfica de tokens de Firebase Authentication (ID tokens).
// Referencia: https://firebase.google.com/docs/auth/admin/verify-id-tokens
//
// COPIA ADAPTADA de cloudflare/imagekit-upload-auth/src/firebase.js. Se copió
// (no se importa) para que ambos Workers sigan siendo independientes: cambiar
// uno no puede afectar al otro. La lógica de verificación es la misma.
// Solo usa WebCrypto, disponible en Workers: sin dependencias.

import { diagExcepcion, diagHttp } from './diagnostico.js';
import { UpstreamError } from './errores.js';

const JWKS_URL = 'https://www.googleapis.com/robot/v1/metadata/jwk/securetoken@system.gserviceaccount.com';
const SKEW_SECONDS = 60; // tolerancia de reloj para iat y auth_time

export class AuthError extends Error {}

let jwksCache = { keys: null, expiraMs: 0 };

/** Solo para pruebas. */
export function resetJwksCache() {
  jwksCache = { keys: null, expiraMs: 0 };
}

function base64UrlToBytes(s) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJson(part) {
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlToBytes(part)));
  } catch {
    throw new AuthError('Token mal formado');
  }
}

async function cargarClaves(fetchFn, nowMs, forzar) {
  if (!forzar && jwksCache.keys && nowMs < jwksCache.expiraMs) return jwksCache.keys;
  let resp;
  try {
    resp = await fetchFn(JWKS_URL);
  } catch (e) {
    throw new UpstreamError('No se pudieron obtener las claves de Firebase (red).', diagExcepcion('verificar_id_token', e));
  }
  if (!resp.ok) throw new UpstreamError(`No se pudieron obtener las claves de Firebase (${resp.status})`, await diagHttp('verificar_id_token', resp));
  const maxAge = /max-age=(\d+)/.exec(resp.headers.get('cache-control') || '');
  const ttl = maxAge ? Number(maxAge[1]) : 3600;
  const { keys } = await resp.json();
  jwksCache = { keys, expiraMs: nowMs + ttl * 1000 };
  return keys;
}

/**
 * Valida el ID token y devuelve su payload. Comprueba, en este orden: forma,
 * algoritmo RS256, firma con la clave pública de Google (por `kid`), `exp`,
 * `iat`, `aud` (= id del proyecto), `iss`, `sub` (UID) y `auth_time`.
 * Lanza [AuthError] si algo no cuadra. Otros errores (red al pedir las
 * claves) se propagan como Error normal y el Worker responde 503.
 */
export async function verifyIdToken(token, { projectId, fetchFn = fetch, nowMs = Date.now() }) {
  if (typeof token !== 'string' || token.length > 4096) throw new AuthError('Token inválido');
  const partes = token.split('.');
  if (partes.length !== 3 || partes.some((p) => p.length === 0)) throw new AuthError('Token mal formado');

  const header = decodeJson(partes[0]);
  const payload = decodeJson(partes[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new AuthError('Algoritmo no admitido');

  // Firma: se busca la clave por kid; si no está, se refresca una vez (rotación de claves).
  let keys = await cargarClaves(fetchFn, nowMs, false);
  let jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    keys = await cargarClaves(fetchFn, nowMs, true);
    jwk = keys.find((k) => k.kid === header.kid);
  }
  if (!jwk) throw new AuthError('Clave de firma desconocida');

  const clave = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const firmaOk = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    clave,
    base64UrlToBytes(partes[2]),
    new TextEncoder().encode(`${partes[0]}.${partes[1]}`),
  );
  if (!firmaOk) throw new AuthError('Firma inválida');

  const ahora = Math.floor(nowMs / 1000);
  if (typeof payload.exp !== 'number' || payload.exp <= ahora) throw new AuthError('Token expirado');
  if (typeof payload.iat !== 'number' || payload.iat > ahora + SKEW_SECONDS) throw new AuthError('Token emitido en el futuro');
  if (payload.aud !== projectId) throw new AuthError('Proyecto incorrecto');
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) throw new AuthError('Emisor incorrecto');
  if (typeof payload.sub !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(payload.sub)) throw new AuthError('UID inválido');
  if (typeof payload.auth_time !== 'number' || payload.auth_time > ahora + SKEW_SECONDS) throw new AuthError('auth_time inválido');
  return payload;
}
