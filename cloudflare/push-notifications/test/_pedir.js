import { handle } from '../src/index.js';
import { ENDPOINT, NOW_MS } from './_helpers.js';

export const CHAT = (messageId = 'm1', connectionId = 'uid_comprador_lot1') => ({ tipo: 'chatMessage', connectionId, messageId });
export const COT = (eventId = 'e1', quoteId = 'q1') => ({ tipo: 'quoteEvent', quoteId, eventId });

/**
 * Llama a handle() con el mundo simulado. Por defecto autentica al comprador.
 * `token: null` → sin cabecera Authorization. `cuerpo` admite un string crudo.
 */
export async function pedir(w, { uid, token, cuerpo = CHAT(), metodo = 'POST', url = ENDPOINT, env, nowMs = NOW_MS, log = () => {}, fetch: fetchInyectado } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token !== null) headers.Authorization = `Bearer ${token ?? (await w.idToken(uid))}`;
  const init = { method: metodo, headers };
  if (metodo !== 'GET') init.body = typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo);
  const resp = await handle(new Request(url, init), env ?? w.env, { fetch: fetchInyectado ?? w.fetch, nowMs, log });
  return { status: resp.status, cuerpo: await resp.json() };
}
