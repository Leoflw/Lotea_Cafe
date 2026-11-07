// Token OAuth de la cuenta de servicio: JWT RS256 válido, caché y errores de configuración.
import test from 'node:test';
import assert from 'node:assert/strict';
import { resetAuthCache } from '../src/google-auth.js';
import { NOW_MS, mundoDeChat, nuevaCuentaDeServicio } from './_helpers.js';
import { CHAT, pedir } from './_pedir.js';

test('el JWT de la cuenta de servicio es RS256, con los alcances y la duración correctos (lo verifica el OAuth simulado)', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(w.llamadasOauth, 1); // el simulado devuelve 400 invalid_grant si algo no cuadra
});

test('caché: varias peticiones seguidas usan UN solo access token', async () => {
  const w = await mundoDeChat();
  for (let i = 1; i <= 4; i++) {
    w.ponerConexion({ ultimoMensajeId: `n${i}`, ultimoMensajeDe: 'uid_comprador' });
    w.ponerMensaje(`n${i}`);
    assert.equal((await pedir(w, { cuerpo: CHAT(`n${i}`) })).status, 200);
  }
  assert.equal(w.llamadasOauth, 1);
});

test('peticiones SIMULTÁNEAS en frío comparten una sola renovación', async () => {
  const w = await mundoDeChat();
  for (let i = 1; i <= 3; i++) w.ponerMensaje(`p${i}`);
  w.ponerConexion({ ultimoMensajeId: 'p1', ultimoMensajeDe: 'uid_comprador' });
  // Tres avisos del mismo evento a la vez: una sola llamada OAuth.
  await Promise.all([pedir(w, { cuerpo: CHAT('p1') }), pedir(w, { cuerpo: CHAT('p1') }), pedir(w, { cuerpo: CHAT('p1') })]);
  assert.equal(w.llamadasOauth, 1);
});

test('el token se renueva cuando está a punto de caducar (margen de 5 min)', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  assert.equal(w.llamadasOauth, 1);
  w.ponerConexion({ ultimoMensajeId: 'm2', ultimoMensajeDe: 'uid_comprador' });
  w.ponerMensaje('m2', { edadMs: -3300 * 1000 + 2000 }); // mensaje reciente respecto al reloj adelantado
  // 3300 s después (> 3599 − 300) el access token cacheado ya no se reutiliza.
  const r = await pedir(w, { cuerpo: CHAT('m2'), nowMs: NOW_MS + 3300 * 1000, token: await w.idToken('uid_comprador', { iat: Math.floor(NOW_MS / 1000) + 3290, exp: Math.floor(NOW_MS / 1000) + 6000, auth_time: Math.floor(NOW_MS / 1000) }) });
  assert.equal(r.status, 200, JSON.stringify(r.cuerpo));
  assert.equal(w.llamadasOauth, 2);
});

test('cuenta de servicio de OTRO proyecto → 500 y no se envía nada', async () => {
  const w = await mundoDeChat();
  const otra = await nuevaCuentaDeServicio('otro-proyecto');
  resetAuthCache();
  const r = await pedir(w, { env: { ...w.env, FCM_SERVICE_ACCOUNT_JSON: otra.json } });
  assert.equal(r.status, 500);
  assert.equal(w.enviados.length, 0);
});

test('secreto con JSON inválido o sin clave → 500 sin filtrar el contenido', async () => {
  for (const malo of ['{no json', '{}', JSON.stringify({ project_id: 'lotea-cafe', client_email: 'a@b.c', private_key: 'no-es-pem' })]) {
    const w = await mundoDeChat();
    resetAuthCache();
    const r = await pedir(w, { env: { ...w.env, FCM_SERVICE_ACCOUNT_JSON: malo } });
    assert.equal(r.status, 500);
    assert.equal(JSON.stringify(r.cuerpo).includes('private_key'), false);
    assert.equal(w.enviados.length, 0);
  }
});

test('Google rechaza las credenciales (invalid_grant) → 500 y se libera la deduplicación', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 });
  const r = await pedir(w);
  assert.equal(r.status, 500);
  assert.equal(w.enviados.length, 0);
  assert.equal(w.dedupe().length, 0);
});

test('OAuth caído temporalmente (503) → 503 reintentable', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => new Response('{}', { status: 503 });
  const r = await pedir(w);
  assert.equal(r.status, 503);
  assert.equal(r.cuerpo.reintentable, true);
});
