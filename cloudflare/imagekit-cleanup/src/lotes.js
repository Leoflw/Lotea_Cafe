// Eliminación completa de un lote: solicitud users/{uid}/pendingLotDeletions/{lotId}.
//
// POLÍTICA (ver IMAGEKIT_CLEANUP.md):
//  - Al eliminar un lote, las copias históricas `loteFoto` de SUS solicitudes de interés y
//    cotizaciones quedan en `null`. Esa limpieza la hace SOLO este Worker, con su cuenta de
//    servicio; las reglas de Firestore no permiten a nadie del cliente cambiar `loteFoto`.
//  - Después se borra el lote y las fotos que solo retenía el historial se vuelven a evaluar
//    (pasan de «retenida» a «pendiente») y se borran de ImageKit si ya nadie las usa.
//
// Cada paso es idempotente y el orden es recuperable: si la ejecución se interrumpe en
// cualquier punto, la solicitud sigue en la cola y al repetirla se completa lo que faltaba
// (sin tocar nada dos veces). Estados: igual que la cola de fotos (ver cleanup.js).
//
// Seguridad: la solicitud la escribe el cliente, así que no se fía de ella. El lote debe
// pertenecer a quien la pidió (sellerId == uid); y las consultas de negociaciones llevan
// SIEMPRE `sellerId == uid`, de modo que nunca se toca el historial de otra persona.

import { ErrorConfig, ErrorTemporal } from './errores.js';
import { PhotoId, MAX_INTENTOS, esProcesable, esperaTrasIntento } from './cleanup.js';
import {
  actualizarCola, anularLoteFoto, borrarLote, crearSolicitudesDeFoto, entero, historicosConFoto,
  leerLote, liberarRetenidas, partesDeCola, texto, vEntero, vNulo, vTexto, vTiempo,
} from './firestore.js';

export const COLECCION = 'pendingLotDeletions';
export const LIMITE_HISTORICOS = 100; // por consulta y ejecución (un solo commit de hasta 100 escrituras)
const LOTE_ID_RE = /^[A-Za-z0-9]{1,128}$/;

function idsDeFotos(lote) {
  const lista = lote?.fields?.fotosStoragePaths?.arrayValue?.values ?? [];
  const ids = lista.map((v) => v.stringValue).filter((x) => typeof x === 'string' && PhotoId.test(x));
  return [...new Set(ids)];
}

/**
 * Procesa una solicitud de eliminación de lote. Devuelve
 * 'completado' | 'rechazado' | 'reintentar' | 'fallido' | 'omitido'.
 */
export async function procesarBorradoLote(env, doc, deps) {
  const partes = partesDeCola(doc.name, COLECCION);
  if (!partes) return 'omitido';
  const { uid, id: lotId } = partes;
  const nowMs = deps.nowMs;
  if (!esProcesable(doc, nowMs)) return 'omitido';

  const reabierta = texto(doc, 'estado') === 'pendiente' && entero(doc, 'intentos') >= MAX_INTENTOS;
  const previos = reabierta ? 0 : entero(doc, 'intentos');
  const intento = previos + 1;
  const opciones = (extra = {}) => ({ coleccion: COLECCION, ...extra });

  let actual;
  try {
    actual = await actualizarCola(
      env, uid, lotId,
      {
        estado: vTexto('procesando'),
        intentos: vEntero(intento),
        leaseUntil: vTiempo(nowMs + 2 * 60 * 1000),
        updatedAt: vTiempo(nowMs),
        // Reabierta por la app tras «fallido»: se descarta el error y la espera del ciclo anterior.
        ...(reabierta ? { ultimoError: vNulo(), nextAttemptAt: vNulo(), motivo: vNulo() } : {}),
      },
      opciones({ updateTime: doc.updateTime }),
      deps,
    );
  } catch (e) {
    if (e instanceof ErrorConfig) throw e;
    return 'omitido';
  }
  if (!actual) return 'omitido';

  const cerrar = (estado, extra = {}) =>
    actualizarCola(
      env, uid, lotId,
      { estado: vTexto(estado), updatedAt: vTiempo(nowMs), leaseUntil: vNulo(), nextAttemptAt: vNulo(), ultimoError: vNulo(), ...extra },
      opciones(),
      deps,
    );

  try {
    if (!LOTE_ID_RE.test(lotId)) {
      await cerrar('rechazado', { motivo: vTexto('loteId_invalido'), intentos: vEntero(0) });
      return 'rechazado';
    }

    // 1) El lote debe ser del solicitante. Si ya no existe, el paso 4 ya se hizo antes.
    const lote = await leerLote(env, lotId, deps);
    if (lote && texto(lote, 'sellerId') !== uid) {
      await cerrar('rechazado', { motivo: vTexto('no_es_del_usuario'), intentos: vEntero(0) });
      return 'rechazado';
    }

    // 2) Red de seguridad: si el lote aún tiene fotos que la app no encoló, se encolan aquí.
    if (lote) await crearSolicitudesDeFoto(env, uid, lotId, idsDeFotos(lote), nowMs, deps);

    // 3) Copias históricas → null (solo `loteFoto`, solo negociaciones DE ESTE VENDEDOR sobre este lote).
    let hayMas = false;
    for (const coleccion of ['interestRequests', 'quotes']) {
      const docs = await historicosConFoto(env, coleccion, { lotId, uid }, LIMITE_HISTORICOS, deps);
      await anularLoteFoto(env, docs, deps);
      if (docs.length >= LIMITE_HISTORICOS) hayMas = true;
    }
    if (hayMas) {
      // Quedan más: se continúa en la siguiente ejecución sin gastar un intento.
      await cerrar('pendiente', { intentos: vEntero(previos) });
      return 'reintentar';
    }

    // 4) Borrar el lote (404 = ya borrado).
    if (lote) await borrarLote(env, lotId, deps);

    // 5) Las fotos que solo retenía el historial se vuelven a evaluar.
    await liberarRetenidas(env, uid, lotId, nowMs, deps);

    await cerrar('completado', { resueltoAt: vTiempo(nowMs), intentos: vEntero(0) });
    return 'completado';
  } catch (e) {
    if (e instanceof ErrorConfig) throw e;
    const codigo = e instanceof ErrorTemporal ? e.codigo : 'error_interno';
    try {
      if (intento >= MAX_INTENTOS) {
        await cerrar('fallido', { ultimoError: vTexto(codigo) });
        return 'fallido';
      }
      await cerrar('errorTemporal', { ultimoError: vTexto(codigo), nextAttemptAt: vTiempo(nowMs + esperaTrasIntento(intento)) });
      return 'reintentar';
    } catch {
      return 'reintentar';
    }
  }
}
