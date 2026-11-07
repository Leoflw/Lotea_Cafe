// Autenticación (token ausente, inválido, de otro proyecto…), método, ruta y configuración.
import test from 'node:test';
import assert from 'node:assert/strict';
import { COMPRADOR, NOW, firmarIdToken, mundoDeChat, nuevaClaveGoogle, payloadBase } from './_helpers.js';
import { pedir } from './_pedir.js';

test('sin cabecera Authorization → 401 y nada se envía', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w, { token: null });
  assert.equal(r.status, 401);
  assert.equal(w.enviados.length, 0);
});

test('token con basura → 401', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedir(w, { token: 'esto-no-es-un-jwt' })).status, 401);
  assert.equal((await pedir(w, { token: 'a.b.c' })).status, 401);
  assert.equal(w.enviados.length, 0);
});

test('token firmado por otra clave (firma inválida) → 401', async () => {
  const w = await mundoDeChat();
  const otra = await nuevaClaveGoogle('kid-1');
  const falso = await firmarIdToken(otra.privada, 'kid-1', payloadBase());
  assert.equal((await pedir(w, { token: falso })).status, 401);
});

test('token de OTRO proyecto de Firebase (aud) → 401', async () => {
  const w = await mundoDeChat();
  const t = await w.idToken(COMPRADOR, { aud: 'otro-proyecto', iss: 'https://securetoken.google.com/otro-proyecto' });
  const r = await pedir(w, { token: t });
  assert.equal(r.status, 401);
  assert.equal(w.enviados.length, 0);
});

test('emisor incorrecto → 401', async () => {
  const w = await mundoDeChat();
  const t = await w.idToken(COMPRADOR, { iss: 'https://evil.example.com/lotea-cafe' });
  assert.equal((await pedir(w, { token: t })).status, 401);
});

test('token caducado → 401', async () => {
  const w = await mundoDeChat();
  const t = await w.idToken(COMPRADOR, { exp: NOW - 10 });
  assert.equal((await pedir(w, { token: t })).status, 401);
});

test('UID ausente o inválido → 401', async () => {
  const w = await mundoDeChat();
  const sinSub = await firmarIdToken(w.claveGoogle.privada, 'kid-1', (({ sub, ...resto }) => resto)(payloadBase()));
  assert.equal((await pedir(w, { token: sinSub })).status, 401);
  assert.equal((await pedir(w, { token: await w.idToken('uid/../malo') })).status, 401);
});

test('solo POST /notify: GET → 405, otra ruta → 404 (la ruta / es del Worker de ImageKit, no de este)', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedir(w, { metodo: 'GET' })).status, 405);
  assert.equal((await pedir(w, { url: 'https://push.example.workers.dev/' })).status, 404);
  assert.equal((await pedir(w, { url: 'https://push.example.workers.dev/notify/extra' })).status, 404);
});

test('HTTP plano → 400 salvo ALLOW_HTTP=true', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedir(w, { url: 'http://localhost:8787/notify' })).status, 400);
  assert.equal((await pedir(w, { url: 'http://localhost:8787/notify', env: { ...w.env, ALLOW_HTTP: 'true' } })).status, 200);
});

test('sin el secreto de la cuenta de servicio el Worker responde 500 sin filtrar detalles', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w, { env: { FIREBASE_PROJECT_ID: 'lotea-cafe' } });
  assert.equal(r.status, 500);
  assert.equal(JSON.stringify(r.cuerpo).includes('FCM_SERVICE_ACCOUNT_JSON'), false);
});
