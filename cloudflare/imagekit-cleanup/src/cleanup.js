// Núcleo de la limpieza: procesa UNA solicitud de la cola.
//
// Cola: users/{uid}/pendingFileDeletions/{fileId}. La app crea la solicitud
// (estado «pendiente») en el MISMO lote atómico en que guarda el documento con
// la foto nueva. Este Worker nunca se fía de ella: el contenido de la cola lo
// escribe el cliente, así que cada solicitud se valida desde cero.
//
// Estados (los escribe SOLO el Worker, salvo «pendiente» inicial):
//   pendiente      creada por la app; espera su turno
//   procesando     reclamada por una ejecución (con `leaseUntil`)
//   completado     el archivo ya no existe en ImageKit (borrado ahora o antes)
//   enUso          un lote o perfil VIGENTE aún la referencia: NO se borró. La app puede
//                  volver a pedirla (regla de Firestore: enUso → pendiente)
//   retenida       solo la copia histórica `loteFoto` de una solicitud de interés o de una
//                  cotización la usa: NO se borra para no romper el historial. Se revisa de
//                  nuevo cada RETENIDA_REVISION_MS y cuando se elimina el lote (ver lotes.js)
//   rechazado      no es un archivo de este usuario o el id no es válido
//   errorTemporal  fallo recuperable; se reintenta tras `nextAttemptAt`
//   fallido        agotó MAX_INTENTOS; la app puede reabrirla (fallido → pendiente)
//
// Seguridad: el archivo se borra solo si (1) ImageKit confirma que su ruta está
// dentro de {raíz}/users/{uid}/{lots|profile} del usuario DUEÑO de la solicitud,
// (2) ningún lote, perfil, solicitud de interés ni cotización lo referencia y (3) las
// consultas de referencias no fallaron. Es idempotente: un 404 de ImageKit cuenta como «ya borrado».

import { ErrorConfig, ErrorTemporal } from './errores.js';
import { actualizarCola, entero, marcaMs, partesDeCola, referenciadaPor, texto, vEntero, vNulo, vTexto, vTiempo } from './firestore.js';
import { borrarArchivo, detallesArchivo } from './imagekit.js';

export const MAX_INTENTOS = 6;
export const LEASE_MS = 2 * 60 * 1000;
const ESPERA_BASE_MS = 5 * 60 * 1000;
const ESPERA_MAX_MS = 6 * 60 * 60 * 1000;
export const RETENIDA_REVISION_MS = 7 * 24 * 60 * 60 * 1000;
export const FILEID_RE = /^[A-Za-z0-9_-]{8,64}$/;
export const PhotoId = FILEID_RE; // alias usado por lotes.js
const CARPETAS = ['lots', 'profile'];

export const esperaTrasIntento = (intento) => Math.min(ESPERA_BASE_MS * 2 ** (intento - 1), ESPERA_MAX_MS);

/** ¿Está la ruta dentro de la carpeta del usuario? (raíz sin barra final). */
export function esDelUsuario(filePath, uid, raiz) {
  if (typeof filePath !== 'string' || filePath.includes('..')) return false;
  const prefijo = `${raiz.replace(/\/+$/, '')}/users/${uid}/`;
  if (!filePath.startsWith(prefijo)) return false;
  const resto = filePath.slice(prefijo.length).split('/');
  return resto.length >= 2 && CARPETAS.includes(resto[0]) && resto.slice(1).every((s) => s.length > 0);
}

/** ¿Le toca procesarse ahora a esta solicitud? */
export function esProcesable(doc, nowMs) {
  switch (texto(doc, 'estado')) {
    case 'pendiente':
      return true;
    case 'errorTemporal':
      return (marcaMs(doc, 'nextAttemptAt') ?? 0) <= nowMs;
    case 'procesando':
      return (marcaMs(doc, 'leaseUntil') ?? 0) <= nowMs; // el proceso anterior murió
    case 'retenida':
      return (marcaMs(doc, 'nextAttemptAt') ?? 0) <= nowMs; // revisión periódica
    default:
      return false;
  }
}


/**
 * Procesa un documento de la cola. Devuelve
 * 'completado' | 'enUso' | 'retenida' | 'rechazado' | 'reintentar' | 'fallido' | 'omitido'.
 * No lanza por fallos de ImageKit/Firestore: los convierte en reintento.
 */
export async function procesarSolicitud(env, doc, deps) {
  const partes = partesDeCola(doc.name);
  if (!partes) return 'omitido';
  const { uid, id } = partes;
  const nowMs = deps.nowMs;
  if (!esProcesable(doc, nowMs)) return 'omitido';

  // Una solicitud reabierta por la app tras agotar los intentos (fallido → pendiente)
  // empieza de cero.
  const reabierta = texto(doc, 'estado') === 'pendiente' && entero(doc, 'intentos') >= MAX_INTENTOS;
  const previos = reabierta ? 0 : entero(doc, 'intentos');
  const intento = previos + 1;
  const raiz = env.IMAGEKIT_FOLDER_ROOT || '/lotea-cafe';

  // 1) Reclamar (lease + precondición): si otra ejecución llegó antes, se omite.
  let actual;
  try {
    actual = await actualizarCola(
      env,
      uid,
      id,
      {
        estado: vTexto('procesando'),
        intentos: vEntero(intento),
        leaseUntil: vTiempo(nowMs + LEASE_MS),
        updatedAt: vTiempo(nowMs),
        // Reabierta por la app tras «fallido»: se descarta el error y la espera del ciclo anterior.
        ...(reabierta ? { ultimoError: vNulo(), nextAttemptAt: vNulo(), motivo: vNulo() } : {}),
      },
      { updateTime: doc.updateTime },
      deps,
    );
  } catch (e) {
    if (e instanceof ErrorConfig) throw e;
    return 'omitido'; // no se pudo ni reclamar: otra ejecución o el cron lo reintentará
  }
  if (!actual) return 'omitido';

  const cerrar = (estado, extra = {}) =>
    actualizarCola(
      env,
      uid,
      id,
      {
        estado: vTexto(estado),
        updatedAt: vTiempo(nowMs),
        leaseUntil: vNulo(),
        nextAttemptAt: vNulo(),
        ultimoError: vNulo(),
        ...extra,
      },
      {},
      deps,
    );

  try {
    // 2) El id debe tener la forma de un fileId de ImageKit.
    if (!FILEID_RE.test(id)) {
      await cerrar('rechazado', { motivo: vTexto('fileId_invalido'), intentos: vEntero(0) });
      return 'rechazado';
    }

    // 3) ImageKit dice dónde está el archivo de verdad. Si no existe, ya está limpio.
    const det = await detallesArchivo(env, id, deps.fetchFn);
    if (!det.existe) {
      await cerrar('completado', { resueltoAt: vTiempo(nowMs), motivo: vTexto('ya_no_existia') });
      return 'completado';
    }

    // 4) Pertenencia: la ruta real debe estar bajo la carpeta DEL DUEÑO de la solicitud.
    if (det.fileId !== id || !esDelUsuario(det.filePath, uid, raiz)) {
      await cerrar('rechazado', { motivo: vTexto('no_es_del_usuario'), intentos: vEntero(0) });
      return 'rechazado';
    }

    // 5) ¿Sigue en uso? Hace falta la URL para comprobar las copias históricas: sin ella
    //    no se puede estar seguro, así que no se borra (falla cerrado, se reintenta).
    if (!det.url) throw new ErrorTemporal('imagekit_respuesta');
    const uso = await referenciadaPor(env, { fileId: id, url: det.url }, deps);
    if (uso === 'actual') {
      // intentos en 0: si el vendedor la quita de verdad más adelante, la app puede
      // volver a pedirla (regla de Firestore: enUso → pendiente).
      await cerrar('enUso', { motivo: vTexto('referenciada'), intentos: vEntero(0) });
      return 'enUso';
    }
    if (uso === 'historica') {
      // Solo la usa el historial de negociaciones. Se conserva; se vuelve a evaluar sola.
      await cerrar('retenida', { motivo: vTexto('historial'), intentos: vEntero(0), nextAttemptAt: vTiempo(nowMs + RETENIDA_REVISION_MS) });
      return 'retenida';
    }

    // 6) Borrado remoto.
    const r = await borrarArchivo(env, id, deps.fetchFn);
    await cerrar('completado', { resueltoAt: vTiempo(nowMs), motivo: vTexto(r === 'borrado' ? 'borrado' : 'ya_no_existia') });
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
      // Ni siquiera se pudo anotar: el lease vence en 2 min y se retoma solo.
      return 'reintentar';
    }
  }
}

