// Deduplicación PERSISTENTE de notificaciones en Firestore (colección
// `pushDedupe`, solo accesible con la cuenta de servicio; las reglas de
// Firestore la bloquean para los clientes).
//
// Un reintento HTTP del mismo evento no envía otra notificación aunque llegue
// a otra instancia del Worker, porque el estado vive en Firestore, no en la
// memoria del Worker. Máquina de estados de cada documento:
//
//   (no existe) --reclamar--> «enviando» --marcarEnviado--> «enviado»
//                                 |
//                                 +--liberar (fallo temporal sin ningún envío)--> (se borra)
//
// - «enviando» con menos de LEASE_MS: otra petición está procesando el evento
//   → 202 «enCurso» (no se envía nada).
// - «enviando» con más de LEASE_MS: la petición anterior murió a medias; se
//   toma el relevo con una escritura condicionada a updateTime (solo una gana).
// - «enviado»: duplicado → 200 «duplicado».
//
// Comportamiento ante errores de FCM (ver README.md):
//  - Ningún dispositivo recibió el aviso por errores TEMPORALES o de
//    CONFIGURACIÓN → se libera el registro: el reintento puede enviar.
//  - Al menos un dispositivo lo recibió → queda «enviado»: reintentar duplicaría
//    el aviso en los dispositivos que sí lo recibieron.
//  - Solo hubo tokens inválidos (ya borrados) → queda «enviado»: no hay a quién
//    reenviar.

import { diagHttp } from './diagnostico.js';
import { UpstreamError } from './errores.js';
import { fetchConCuenta } from './google-auth.js';
import { ruta } from './firestore.js';

export const LEASE_MS = 60_000;
export const RETENCION_MS = 7 * 24 * 3600 * 1000; // para la política TTL opcional sobre `expiraEn`

/** Id de documento estable y seguro derivado del evento (SHA-256 en hex). */
export async function claveDeEvento(tipo, a, b) {
  const datos = new TextEncoder().encode(`${tipo}|${a}|${b}`);
  const hash = await crypto.subtle.digest('SHA-256', datos);
  return [...new Uint8Array(hash)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

const campos = (estado, tipo, ahoraMs) => ({
  estado: { stringValue: estado },
  tipo: { stringValue: tipo },
  claimedAtMs: { integerValue: String(ahoraMs) },
  expiraEn: { timestampValue: new Date(ahoraMs + RETENCION_MS).toISOString() },
});

async function crear(env, proyecto, id, tipo, deps) {
  const url = `${ruta(proyecto, 'pushDedupe')}?documentId=${encodeURIComponent(id)}`;
  return fetchConCuenta(env, url, { method: 'POST', body: JSON.stringify({ fields: campos('enviando', tipo, deps.nowMs) }) }, deps, 'firestore_dedupe_crear');
}

/** Intenta quedarse con el evento. Devuelve 'nuevo' | 'duplicado' | 'enCurso'. */
export async function reclamar(env, proyecto, id, tipo, deps) {
  for (let intento = 0; intento < 2; intento++) {
    const resp = await crear(env, proyecto, id, tipo, deps);
    if (resp.ok) return 'nuevo';
    if (resp.status !== 409) throw new UpstreamError(`Firestore respondió ${resp.status} al registrar la deduplicación.`, await diagHttp('firestore_dedupe_crear', resp));

    // Ya existía: se mira en qué estado quedó.
    const lectura = await fetchConCuenta(env, ruta(proyecto, 'pushDedupe', id), { method: 'GET' }, deps, 'firestore_dedupe_leer');
    if (lectura.status === 404) continue; // se liberó entretanto: se vuelve a intentar crear
    if (!lectura.ok) throw new UpstreamError(`Firestore respondió ${lectura.status} al leer la deduplicación.`, await diagHttp('firestore_dedupe_leer', lectura));
    const doc = await lectura.json();
    if (doc.fields?.estado?.stringValue === 'enviado') return 'duplicado';

    const desde = Number(doc.fields?.claimedAtMs?.integerValue ?? 0);
    if (deps.nowMs - desde < LEASE_MS) return 'enCurso';

    // Relevo de un intento que quedó a medias: solo gana UNA petición (precondición por updateTime).
    const url =
      `${ruta(proyecto, 'pushDedupe', id)}?currentDocument.updateTime=${encodeURIComponent(doc.updateTime)}` +
      '&updateMask.fieldPaths=estado&updateMask.fieldPaths=claimedAtMs';
    const relevo = await fetchConCuenta(
      env,
      url,
      { method: 'PATCH', body: JSON.stringify({ fields: { estado: { stringValue: 'enviando' }, claimedAtMs: { integerValue: String(deps.nowMs) } } }) },
      deps,
      'firestore_dedupe_relevo',
    );
    if (relevo.ok) return 'nuevo';
    if ([400, 409, 412].includes(relevo.status)) return 'enCurso'; // otra petición se adelantó
    throw new UpstreamError(`Firestore respondió ${relevo.status} al tomar el relevo.`, await diagHttp('firestore_dedupe_relevo', relevo));
  }
  return 'enCurso';
}

/** Marca el evento como entregado. Un fallo aquí no cambia lo ya enviado. */
export async function marcarEnviado(env, proyecto, id, deps) {
  const url = `${ruta(proyecto, 'pushDedupe', id)}?updateMask.fieldPaths=estado`;
  const resp = await fetchConCuenta(env, url, { method: 'PATCH', body: JSON.stringify({ fields: { estado: { stringValue: 'enviado' } } }) }, deps, 'firestore_dedupe_marcar');
  return resp.ok;
}

/** Libera el evento para que un reintento pueda enviarlo. */
export async function liberar(env, proyecto, id, deps) {
  const resp = await fetchConCuenta(env, ruta(proyecto, 'pushDedupe', id), { method: 'DELETE' }, deps, 'firestore_dedupe_liberar');
  return resp.ok || resp.status === 404;
}
