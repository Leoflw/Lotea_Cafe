// Comprobación de conectividad AUTENTICADA, ejecutada desde el propio Worker.
//
//   GET /diagnostico
//   Authorization: Bearer <DIAGNOSTICO_TOKEN>
//
// Es OPCIONAL y está DESACTIVADA por defecto: solo existe si el Worker tiene el secreto
// `DIAGNOSTICO_TOKEN` (24 caracteres o más). Sin él, la ruta se comporta como antes
// (405 al GET, 404 al POST). Pensada para activarla un rato, verificar y borrar el secreto.
//
// Qué hace (solo LECTURAS, ningún dato de usuario, ningún envío FCM):
//   1. salida_publica       GET sin credenciales a las claves públicas de Firebase.
//   2. oauth                canje del JWT de la cuenta de servicio por un access token.
//   3. firestore_autenticado GET de un documento FIJO que no existe (pushDedupe/diagnostico-conectividad)
//                           con el mismo `fetchConCuenta` que usa /notify. 200 y 404 cuentan como
//                           correcto: ambos prueban que la llamada autenticada llegó y se autorizó.
// La respuesta solo lleva resultados y códigos de lista permitida (ver diagnostico.js).

import { sanear } from './diagnostico.js';
import { diagExcepcion, diagHttp } from './diagnostico.js';
import { fetchConCuenta, obtenerAccessToken } from './google-auth.js';
import { ruta } from './firestore.js';

export const DIAGNOSTICO_TOKEN_MIN = 24;
const JWKS_URL = 'https://www.googleapis.com/robot/v1/metadata/jwk/securetoken@system.gserviceaccount.com';
export const DOC_DIAGNOSTICO = ['pushDedupe', 'diagnostico-conectividad'];

/** ¿Está activada la ruta? Solo con un secreto suficientemente largo. */
export const diagnosticoActivo = (env) => typeof env.DIAGNOSTICO_TOKEN === 'string' && env.DIAGNOSTICO_TOKEN.length >= DIAGNOSTICO_TOKEN_MIN;

async function sha256(texto) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto)));
}

/** Comparación en tiempo constante (se comparan los SHA-256, de igual longitud). */
export async function tokenCorrecto(recibido, esperado) {
  const [a, b] = await Promise.all([sha256(String(recibido)), sha256(String(esperado))]);
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) diferencia |= a[i] ^ b[i];
  return diferencia === 0;
}

const ok = (paso, extra = {}) => ({ paso, resultado: 'ok', ...extra });
const fallo = (paso, diag) => ({ paso, resultado: 'fallo', ...sanear(diag) });

export async function comprobarConectividad(env, proyecto, deps) {
  const pasos = [];
  const { fetchFn } = deps;

  // 1) Salida a Internet sin credenciales (descarta un problema general de red).
  try {
    const r = await fetchFn(JWKS_URL);
    pasos.push(r.ok ? ok('salida_publica', { http: r.status }) : fallo('salida_publica', await diagHttp('diagnostico_salida', r)));
  } catch (e) {
    pasos.push(fallo('salida_publica', diagExcepcion('diagnostico_salida', e)));
  }

  // 2) OAuth de la cuenta de servicio.
  try {
    await obtenerAccessToken(env, deps);
    pasos.push(ok('oauth'));
  } catch (e) {
    pasos.push(fallo('oauth', e?.diag ?? { etapa: 'oauth_token', servicio: 'oauth' }));
  }

  // 3) Lectura AUTENTICADA de Firestore con la misma función que usa /notify.
  try {
    const r = await fetchConCuenta(env, ruta(proyecto, ...DOC_DIAGNOSTICO), { method: 'GET' }, deps, 'diagnostico_firestore');
    if (r.ok || r.status === 404) pasos.push(ok('firestore_autenticado', { http: r.status }));
    else pasos.push(fallo('firestore_autenticado', await diagHttp('diagnostico_firestore', r)));
  } catch (e) {
    pasos.push(fallo('firestore_autenticado', e?.diag ?? { etapa: 'diagnostico_firestore', causa: 'red' }));
  }

  return { ok: pasos.every((p) => p.resultado === 'ok'), pasos };
}
