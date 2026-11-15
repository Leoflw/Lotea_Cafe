// Llamadas a la API de gestión de ImageKit con la clave privada (secreto del
// Worker). https://imagekit.io/docs/api-reference/media-api
//  - GET    /v1/files/{fileId}/details  → dónde está el archivo (filePath) y su url
//  - DELETE /v1/files/{fileId}          → 204 si lo borra, 404 si ya no existe
// Un 404 se trata como «ya borrado»: eso hace idempotente la limpieza.

import { ErrorTemporal } from './errores.js';

const API = 'https://api.imagekit.io/v1';
const cabecera = (clavePrivada) => ({ Authorization: `Basic ${btoa(`${clavePrivada}:`)}` });

async function llamar(env, ruta, metodo, fetchFn) {
  let resp;
  try {
    resp = await fetchFn(`${API}${ruta}`, { method: metodo, headers: cabecera(env.IMAGEKIT_PRIVATE_KEY) });
  } catch {
    throw new ErrorTemporal('imagekit_red');
  }
  if (resp.status === 429) throw new ErrorTemporal('imagekit_429');
  if (resp.status >= 500) throw new ErrorTemporal('imagekit_5xx');
  // 401/403: clave mal configurada o revocada. Se reintenta (puede corregirse) y
  // tras MAX_INTENTOS queda «fallido» con este código.
  if (resp.status === 401 || resp.status === 403) throw new ErrorTemporal('imagekit_credenciales');
  return resp;
}

/** { existe:false } si ImageKit responde 404; si no { existe:true, filePath, url, fileId }. */
export async function detallesArchivo(env, fileId, fetchFn) {
  const resp = await llamar(env, `/files/${encodeURIComponent(fileId)}/details`, 'GET', fetchFn);
  if (resp.status === 404) return { existe: false };
  if (!resp.ok) throw new ErrorTemporal('imagekit_respuesta');
  let d;
  try {
    d = await resp.json();
  } catch {
    throw new ErrorTemporal('imagekit_respuesta');
  }
  if (typeof d?.filePath !== 'string' || typeof d?.fileId !== 'string') throw new ErrorTemporal('imagekit_respuesta');
  return { existe: true, filePath: d.filePath, url: typeof d.url === 'string' ? d.url : null, fileId: d.fileId };
}

/** 'borrado' | 'yaNoExistia'. */
export async function borrarArchivo(env, fileId, fetchFn) {
  const resp = await llamar(env, `/files/${encodeURIComponent(fileId)}`, 'DELETE', fetchFn);
  if (resp.status === 404) return 'yaNoExistia';
  if (resp.status === 200 || resp.status === 204) return 'borrado';
  throw new ErrorTemporal('imagekit_borrar');
}
