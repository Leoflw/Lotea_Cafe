// Utilidades comunes de las pruebas de transporte y conectividad.
import assert from 'node:assert/strict';
import { COMPRADOR, CONEXION, VENDEDOR } from './_helpers.js';
import { pedir } from './_pedir.js';

export const ENTRADA = { error: 'Servicio temporalmente no disponible. Puedes reintentar.', reintentable: true };
export const json = (estado, cuerpo) => new Response(JSON.stringify(cuerpo), { status: estado, headers: { 'Content-Type': 'application/json' } });
export const googleError = (estado, status) => json(estado, { error: { code: estado, status, message: 'HOSTIL-MENSAJE Bearer ya29.TOKEN-OAUTH-SECRETO' } });

export async function correr(w, opciones = {}) {
  const logs = [];
  const token = opciones.token ?? (await w.idToken());
  const r = await pedir(w, { ...opciones, token, log: (e) => logs.push(e) });
  return { ...r, logs, token };
}
export const errorDe = (logs) => logs.find((l) => l.evento === 'notify_error');

/** Hace que fetch LANCE `error` cuando la URL encaja con `patron` (el resto pasa al mundo simulado). */
export function lanzarEn(w, patron, error) {
  const base = w.fetch;
  w.fetch = async (url, init) => {
    if (patron.test(String(url))) throw error;
    return base(url, init);
  };
}
export const EN_DISPOSITIVOS = /\/deviceTokens\?pageSize/;

export function sinSecretos(w, textoORegistros, token, extras = []) {
  const texto = typeof textoORegistros === 'string' ? textoORegistros : JSON.stringify(textoORegistros);
  const sa = JSON.parse(w.sa.json);
  const prohibidos = [
    'BEGIN PRIVATE KEY', sa.private_key.replace(/-----[A-Z ]+-----|\s/g, '').slice(20, 60), sa.client_email,
    token, token.split('.')[2], 'at_1', 'at_2', 'ya29', 'TOKEN-OAUTH-SECRETO',
    'tokV1', w.tokenValido('tokV1'), 'Bearer', 'Authorization', 'authorization', 'SECRETO-DEL-CHAT',
    'HOSTIL-MENSAJE', 'RED-CAIDA-SECRETO', COMPRADOR, VENDEDOR, CONEXION, ...extras,
  ];
  for (const p of prohibidos) assert.equal(texto.includes(p), false, `el texto contiene «${p}»: ${texto}`);
}
