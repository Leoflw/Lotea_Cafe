// El Worker de ImageKit no se modifica ni se mezcla con este servicio.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { handle as handleImageKit } from '../../imagekit-upload-auth/src/index.js';
import { handle as handlePush } from '../src/index.js';

const aquí = dirname(fileURLToPath(import.meta.url));
const raizPush = join(aquí, '..');
const raizImageKit = join(aquí, '..', '..', 'imagekit-upload-auth');

test('cada Worker tiene su propio nombre y configuración en wrangler.toml', () => {
  const push = readFileSync(join(raizPush, 'wrangler.toml'), 'utf8');
  const ik = readFileSync(join(raizImageKit, 'wrangler.toml'), 'utf8');
  assert.match(push, /^name = "push-notifications"$/m);
  assert.match(ik, /^name = "imagekit-upload-auth"$/m);
  assert.equal(/FCM|push-notifications/.test(ik), false, 'el wrangler.toml de ImageKit no debe mencionar notificaciones');
  assert.equal(/IMAGEKIT/.test(push.replace(/^#.*$/gm, '')), false, 'el wrangler.toml de push no debe llevar variables de ImageKit');
});

test('el código del Worker de ImageKit no menciona FCM ni /notify', () => {
  for (const f of readdirSync(join(raizImageKit, 'src'))) {
    const codigo = readFileSync(join(raizImageKit, 'src', f), 'utf8');
    assert.equal(/FCM|\/notify|deviceTokens|pushDedupe/.test(codigo), false, f);
  }
});

test('el código de push no importa nada del Worker de ImageKit', () => {
  for (const f of readdirSync(join(raizPush, 'src'))) {
    const codigo = readFileSync(join(raizPush, 'src', f), 'utf8');
    assert.equal(/imagekit-upload-auth|imagekit\.js/.test(codigo.replace(/^\s*\/\/.*$/gm, '')), false, f);
  }
});

test('las rutas están separadas: ImageKit atiende «/» y rechaza «/notify»; push hace lo contrario', async () => {
  const envIk = { FIREBASE_PROJECT_ID: 'lotea-cafe', IMAGEKIT_PUBLIC_KEY: 'public_EJEMPLO=', IMAGEKIT_PRIVATE_KEY: 'private_EJEMPLO_NO_REAL=' };
  const post = (url) => new Request(url, { method: 'POST', headers: { Authorization: 'Bearer x.y.z' }, body: '{}' });

  const ikRaiz = await handleImageKit(post('https://ik.example.workers.dev/'), envIk, { fetch: async () => new Response('{}') });
  assert.equal(ikRaiz.status, 401); // llega a la validación del token: la ruta «/» sigue viva
  const ikNotify = await handleImageKit(post('https://ik.example.workers.dev/notify'), envIk, { fetch: async () => new Response('{}') });
  assert.equal(ikNotify.status, 404);

  const envPush = { FIREBASE_PROJECT_ID: 'lotea-cafe', FCM_SERVICE_ACCOUNT_JSON: '{}' };
  const pushRaiz = await handlePush(post('https://push.example.workers.dev/'), envPush, { fetch: async () => new Response('{}'), log: () => {} });
  assert.equal(pushRaiz.status, 404);
});
