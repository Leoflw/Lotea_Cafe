// Cloudflare Worker — autorización de subidas a ImageKit para Lotea Café.
//
// La app Flutter llama aquí con el token de Firebase Authentication del
// usuario. Si el token es válido y el rol lo permite, el Worker devuelve los
// parámetros temporales (token, expire, signature) con los que la app sube la
// foto DIRECTAMENTE a ImageKit. La clave privada de ImageKit nunca sale del
// Worker.

import { AuthError, verifyIdToken } from './firebase.js';
import { firmarSubida } from './imagekit.js';

// Deben coincidir con lib/utils/image_validation.dart.
export const MAX_BYTES = 5 * 1024 * 1024;
export const ALLOWED_TYPES = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

// Finalidades admitidas, el rol que las puede pedir y su subcarpeta en ImageKit.
// Ambas son del vendedor: solo él tiene fotos de perfil de marca y de cafés.
export const PURPOSES = {
  lot: { rol: 'vendedor', carpeta: 'lots' },
  profile: { rol: 'vendedor', carpeta: 'profile' },
};

const EXPIRE_SECONDS = 600; // ImageKit exige menos de 1 hora; 10 min cubren reintentos
const MAX_BODY_BYTES = 2048;
const LIMITE = { max: 30, ventanaMs: 10 * 60 * 1000 }; // 30 autorizaciones / 10 min / usuario

// Limitador "de mejor esfuerzo": vive en la memoria de cada instancia del
// Worker, así que no es global. Frena abusos simples; no sustituye reglas de
// Cloudflare (ver IMAGEKIT_SETUP.md, sección de seguridad).
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
  if (usos.size > 5000) usos.clear(); // evita crecer sin límite
  return false;
}

function json(estado, cuerpo) {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
const error = (estado, mensaje) => json(estado, { error: mensaje });

/** Lee el rol del usuario en Firestore CON SU PROPIO token: las reglas de
 *  seguridad de Firestore son las que deciden si puede leer su documento. */
async function rolDe(uid, idToken, env, fetchFn) {
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/users/${encodeURIComponent(uid)}`;
  const resp = await fetchFn(url, { headers: { Authorization: `Bearer ${idToken}` } });
  if (resp.status === 404 || resp.status === 403) return null;
  if (!resp.ok) throw new Error(`Firestore respondió ${resp.status}`);
  const doc = await resp.json();
  return doc?.fields?.rol?.stringValue ?? null;
}

export async function handle(request, env, deps = {}) {
  const fetchFn = deps.fetch ?? fetch;
  const nowMs = deps.nowMs ?? Date.now();
  const url = new URL(request.url);

  if (url.protocol !== 'https:' && env.ALLOW_HTTP !== 'true') return error(400, 'Se requiere HTTPS.');
  if (request.method !== 'POST') return error(405, 'Método no permitido.');
  if (url.pathname !== '/') return error(404, 'No encontrado.');
  if (!env.FIREBASE_PROJECT_ID || !env.IMAGEKIT_PUBLIC_KEY || !env.IMAGEKIT_PRIVATE_KEY) {
    return error(500, 'El Worker no está configurado.');
  }

  // 1) Autenticación: token de Firebase, validado criptográficamente.
  const cabecera = request.headers.get('Authorization') || '';
  const m = /^Bearer (.+)$/.exec(cabecera);
  if (!m) return error(401, 'Falta el token de sesión.');
  const idToken = m[1].trim();
  let payload;
  try {
    payload = await verifyIdToken(idToken, { projectId: env.FIREBASE_PROJECT_ID, fetchFn, nowMs });
  } catch (e) {
    if (e instanceof AuthError) return error(401, 'Sesión no válida. Inicia sesión de nuevo.');
    return error(503, 'No se pudo validar la sesión. Inténtalo de nuevo.');
  }
  const uid = payload.sub; // El UID sale del token. Nunca del cuerpo de la petición.

  // 2) Cuerpo: tamaño acotado y campos validados.
  const texto = await request.text();
  if (new TextEncoder().encode(texto).length > MAX_BODY_BYTES) return error(413, 'Petición demasiado grande.');
  let cuerpo;
  try {
    cuerpo = JSON.parse(texto);
  } catch {
    return error(400, 'El cuerpo debe ser JSON.');
  }
  if (cuerpo === null || typeof cuerpo !== 'object' || Array.isArray(cuerpo)) return error(400, 'El cuerpo debe ser un objeto JSON.');

  const finalidad = Object.hasOwn(PURPOSES, cuerpo.purpose) ? PURPOSES[cuerpo.purpose] : null;
  if (!finalidad) return error(400, 'Finalidad de subida no válida.');
  if (!Object.hasOwn(ALLOWED_TYPES, cuerpo.contentType)) return error(415, 'Formato no admitido. Usa JPEG, PNG o WebP.');
  if (!Number.isInteger(cuerpo.size) || cuerpo.size < 1) return error(400, 'Tamaño de imagen no válido.');
  if (cuerpo.size > MAX_BYTES) return error(413, 'La imagen supera 5 MB. Elige una más liviana.');

  // 3) Autorización por rol.
  let rol;
  try {
    rol = await rolDe(uid, idToken, env, fetchFn);
  } catch {
    return error(503, 'No se pudo comprobar tu rol. Inténtalo de nuevo.');
  }
  if (rol !== finalidad.rol) return error(403, 'Solo las cuentas de vendedor pueden subir estas fotos.');

  // 4) Freno de abuso (mejor esfuerzo).
  if (excedeLimite(uid, nowMs)) return error(429, 'Demasiadas subidas seguidas. Espera unos minutos.');

  // 5) Parámetros de ImageKit. La carpeta se construye con el UID VERIFICADO.
  const token = crypto.randomUUID();
  const expire = Math.floor(nowMs / 1000) + EXPIRE_SECONDS;
  const signature = await firmarSubida(env.IMAGEKIT_PRIVATE_KEY, token, expire);
  const raiz = (env.IMAGEKIT_FOLDER_ROOT || '/lotea-cafe').replace(/\/+$/, '');
  const fileName = `${cuerpo.purpose}_${nowMs}_${token.slice(0, 8)}.${ALLOWED_TYPES[cuerpo.contentType]}`;

  return json(200, {
    token,
    expire,
    signature,
    publicKey: env.IMAGEKIT_PUBLIC_KEY,
    folder: `${raiz}/users/${uid}/${finalidad.carpeta}`,
    fileName,
    maxBytes: MAX_BYTES,
  });
}

export default {
  fetch(request, env) {
    return handle(request, env);
  },
};
