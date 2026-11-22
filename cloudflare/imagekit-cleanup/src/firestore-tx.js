// Transacciones de Firestore por REST (beginTransaction → lecturas con `transaction` → commit atómico).
//
// Las usa SOLO el ciclo de vida de cuentas (account-deletion.js). Una transacción de lectura y
// escritura hace que Firestore rechace el commit si, desde que se leyó, cambió algún documento
// leído o apareció/desapareció uno que cumple una consulta leída (p. ej. un café publicado nuevo).
// Además cada escritura lleva su precondición (`updateTime` o `exists`) como segunda barrera.
//
// Un commit rechazado por conflicto lanza [ConflictoTransaccion] (el llamador relee y reintenta);
// cualquier otro fallo lanza [ErrorTemporal] con un código corto (nunca el cuerpo de la respuesta).

import { ErrorTemporal } from './errores.js';
import { fetchConCuenta } from './google-auth.js';
import { comoJson, raiz, ruta } from './firestore.js';

export class ConflictoTransaccion extends Error {}

const CABECERA = { 'Content-Type': 'application/json' };

export const filtroIgual = (campo, valor) => ({
  fieldFilter: { field: { fieldPath: campo }, op: 'EQUAL', value: { stringValue: valor } },
});
export const unirY = (filtros) => ({ compositeFilter: { op: 'AND', filters: filtros } });

export async function comenzar(env, deps) {
  const resp = await fetchConCuenta(
    env,
    `${raiz(env.FIREBASE_PROJECT_ID)}:beginTransaction`,
    { method: 'POST', headers: CABECERA, body: JSON.stringify({ options: { readWrite: {} } }) },
    deps,
  );
  const { transaction } = await comoJson(resp, 'firestore_tx_inicio');
  if (typeof transaction !== 'string' || transaction.length === 0) throw new ErrorTemporal('firestore_tx_respuesta');
  return transaction;
}

/** Libera la transacción sin escribir. Mejor esfuerzo: un fallo aquí no cambia el resultado. */
export async function abandonar(env, transaction, deps) {
  try {
    await fetchConCuenta(
      env,
      `${raiz(env.FIREBASE_PROJECT_ID)}:rollback`,
      { method: 'POST', headers: CABECERA, body: JSON.stringify({ transaction }) },
      deps,
    );
  } catch {
    // La transacción caduca sola.
  }
}

/** Documento dentro de la transacción, o null si no existe. */
export async function leerEnTx(env, transaction, segmentos, deps) {
  const url = `${ruta(env.FIREBASE_PROJECT_ID, ...segmentos)}?transaction=${encodeURIComponent(transaction)}`;
  const resp = await fetchConCuenta(env, url, { method: 'GET' }, deps);
  if (resp.status === 404) return null;
  return comoJson(resp, 'firestore_tx_leer');
}

/** Documentos que cumplen la consulta, leídos dentro de la transacción. */
export async function consultarEnTx(env, transaction, coleccion, where, limite, deps) {
  const cuerpo = { structuredQuery: { from: [{ collectionId: coleccion }], where, limit: limite }, transaction };
  const resp = await fetchConCuenta(
    env,
    `${raiz(env.FIREBASE_PROJECT_ID)}:runQuery`,
    { method: 'POST', headers: CABECERA, body: JSON.stringify(cuerpo) },
    deps,
  );
  const filas = await comoJson(resp, 'firestore_tx_consulta');
  return (Array.isArray(filas) ? filas : []).map((f) => f.document).filter(Boolean);
}

/** Aplica todas las escrituras o ninguna. Conflicto o precondición fallida → [ConflictoTransaccion]. */
export async function confirmarTx(env, transaction, writes, deps) {
  const resp = await fetchConCuenta(
    env,
    `${raiz(env.FIREBASE_PROJECT_ID)}:commit`,
    { method: 'POST', headers: CABECERA, body: JSON.stringify({ writes, transaction }) },
    deps,
  );
  if (resp.ok) return;
  let estado = null;
  try {
    estado = (await resp.json())?.error?.status ?? null;
  } catch {
    // cuerpo no JSON
  }
  const conflicto =
    resp.status === 409 || resp.status === 412 || resp.status === 404 ||
    (resp.status === 400 && (estado === 'FAILED_PRECONDITION' || estado === 'ABORTED'));
  if (conflicto) throw new ConflictoTransaccion('firestore_conflicto');
  throw new ErrorTemporal(`firestore_tx_commit_${resp.status === 429 ? '429' : resp.status >= 500 ? '5xx' : resp.status}`);
}
