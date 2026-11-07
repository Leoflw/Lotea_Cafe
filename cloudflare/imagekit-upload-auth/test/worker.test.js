// Pruebas del Worker con `node --test` (Node 20+). No tocan la red: Firebase
// (claves públicas y Firestore) se simula inyectando `fetch`.
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { handle, resetLimitador } from '../src/index.js';
import { resetJwksCache } from '../src/firebase.js';

const PROJECT = 'lotea-cafe';
const PRIVATE_KEY = 'private_EJEMPLO_NO_REAL=';
const ENV = {
  FIREBASE_PROJECT_ID: PROJECT,
  IMAGEKIT_PUBLIC_KEY: 'public_EJEMPLO=',
  IMAGEKIT_PRIVATE_KEY: PRIVATE_KEY,
  IMAGEKIT_FOLDER_ROOT: '/lotea-cafe',
};
const NOW_MS = 1_800_000_000_000;
const NOW = Math.floor(NOW_MS / 1000);

const b64u = (x) => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');

async function nuevaClave(kid) {
  const par = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const jwk = await crypto.subtle.exportKey('jwk', par.publicKey);
  return { privada: par.privateKey, jwk: { ...jwk, kid, alg: 'RS256', use: 'sig' } };
}

async function firmar(clave, kid, payload, headerExtra = {}) {
  const h = b64u({ alg: 'RS256', kid, typ: 'JWT', ...headerExtra });
  const p = b64u(payload);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', clave, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${Buffer.from(sig).toString('base64url')}`;
}

const payloadBase = (extra = {}) => ({
  iss: `https://securetoken.google.com/${PROJECT}`,
  aud: PROJECT,
  auth_time: NOW - 100,
  iat: NOW - 100,
  exp: NOW + 3000,
  sub: 'uid_vendedor_1',
  ...extra,
});

let claveGoogle;
let rolActual;

/** fetch simulado: claves públicas de Google y documento users/{uid} de Firestore. */
function fetchFalso(url) {
  const u = String(url);
  if (u.includes('securetoken@system.gserviceaccount.com')) {
    return Promise.resolve(
      new Response(JSON.stringify({ keys: [claveGoogle.jwk] }), { headers: { 'cache-control': 'public, max-age=3600' } }),
    );
  }
  if (u.includes('firestore.googleapis.com')) {
    if (rolActual === undefined) return Promise.resolve(new Response('{}', { status: 404 }));
    return Promise.resolve(new Response(JSON.stringify({ fields: { rol: { stringValue: rolActual } } })));
  }
  throw new Error(`fetch inesperado: ${u}`);
}

beforeEach(async () => {
  resetJwksCache();
  resetLimitador();
  claveGoogle = await nuevaClave('kid-1');
  rolActual = 'vendedor';
});

async function pedir({ token, cuerpo, metodo = 'POST', env = ENV, url = 'https://w.example.workers.dev/', sinAuth = false } = {}) {
  const t = token ?? (await firmar(claveGoogle.privada, 'kid-1', payloadBase()));
  const headers = { 'Content-Type': 'application/json' };
  if (!sinAuth) headers.Authorization = `Bearer ${t}`;
  const init = { method: metodo, headers };
  if (metodo !== 'GET') init.body = JSON.stringify(cuerpo ?? { purpose: 'lot', contentType: 'image/jpeg', size: 400_000 });
  return handle(new Request(url, init), env, { fetch: fetchFalso, nowMs: NOW_MS });
}

test('autoriza una subida válida y firma con HMAC-SHA1(token+expire)', async () => {
  const r = await pedir();
  assert.equal(r.status, 200);
  const j = await r.json();
  const esperada = createHmac('sha1', PRIVATE_KEY).update(j.token + j.expire).digest('hex');
  assert.equal(j.signature, esperada);
  assert.equal(j.expire, NOW + 600);
  assert.equal(j.publicKey, ENV.IMAGEKIT_PUBLIC_KEY);
  assert.equal(j.folder, '/lotea-cafe/users/uid_vendedor_1/lots');
  assert.match(j.fileName, /^lot_\d+_[0-9a-f]{8}\.jpg$/);
  assert.equal(r.headers.get('cache-control'), 'no-store');
});

test('la respuesta nunca contiene la clave privada', async () => {
  const r = await pedir({ cuerpo: { purpose: 'profile', contentType: 'image/webp', size: 1000 } });
  const texto = await r.text();
  assert.ok(!texto.includes(PRIVATE_KEY));
  assert.ok(!texto.toLowerCase().includes('private'));
});

test('el UID sale del token, no del cuerpo de la petición', async () => {
  const r = await pedir({ cuerpo: { purpose: 'lot', contentType: 'image/png', size: 1000, uid: 'atacante', folder: '/otra' } });
  const j = await r.json();
  assert.equal(r.status, 200);
  assert.equal(j.folder, '/lotea-cafe/users/uid_vendedor_1/lots');
  assert.ok(!JSON.stringify(j).includes('atacante'));
});

test('rechaza peticiones sin token (401)', async () => {
  const r = await pedir({ sinAuth: true });
  assert.equal(r.status, 401);
});

test('rechaza tokens mal formados (401)', async () => {
  for (const t of ['abc', 'a.b', 'a.b.c', '...', 'x'.repeat(5000)]) {
    assert.equal((await pedir({ token: t })).status, 401, t.slice(0, 10));
  }
});

test('rechaza un token firmado con otra clave (401)', async () => {
  const otra = await nuevaClave('kid-1');
  const t = await firmar(otra.privada, 'kid-1', payloadBase());
  assert.equal((await pedir({ token: t })).status, 401);
});

test('rechaza un token manipulado tras firmarse (401)', async () => {
  const t = await firmar(claveGoogle.privada, 'kid-1', payloadBase());
  const [h, , s] = t.split('.');
  const falso = `${h}.${b64u(payloadBase({ sub: 'otro_usuario' }))}.${s}`;
  assert.equal((await pedir({ token: falso })).status, 401);
});

test('rechaza un kid desconocido (401)', async () => {
  const t = await firmar(claveGoogle.privada, 'kid-desconocido', payloadBase());
  assert.equal((await pedir({ token: t })).status, 401);
});

test('rechaza tokens con alg distinto de RS256 (401)', async () => {
  const t = `${b64u({ alg: 'none', kid: 'kid-1' })}.${b64u(payloadBase())}.${b64u('x')}`;
  assert.equal((await pedir({ token: t })).status, 401);
});

for (const [nombre, extra] of [
  ['expirado', { exp: NOW - 1 }],
  ['proyecto incorrecto (aud)', { aud: 'otro-proyecto' }],
  ['emisor incorrecto (iss)', { iss: 'https://securetoken.google.com/otro-proyecto' }],
  ['UID vacío', { sub: '' }],
  ['UID con caracteres peligrosos', { sub: '../../admin' }],
  ['emitido en el futuro', { iat: NOW + 3600 }],
  ['sin auth_time', { auth_time: undefined }],
]) {
  test(`rechaza un token ${nombre} (401)`, async () => {
    const t = await firmar(claveGoogle.privada, 'kid-1', payloadBase(extra));
    assert.equal((await pedir({ token: t })).status, 401);
  });
}

test('un comprador no puede subir fotos de lotes ni de perfil (403)', async () => {
  rolActual = 'comprador';
  for (const purpose of ['lot', 'profile']) {
    const r = await pedir({ cuerpo: { purpose, contentType: 'image/jpeg', size: 1000 } });
    assert.equal(r.status, 403, purpose);
  }
});

test('un usuario sin documento de perfil en Firestore recibe 403', async () => {
  rolActual = undefined;
  assert.equal((await pedir()).status, 403);
});

test('limita tipo, tamaño y finalidad', async () => {
  const casos = [
    [{ purpose: 'lot', contentType: 'image/gif', size: 1000 }, 415],
    [{ purpose: 'lot', contentType: 'application/pdf', size: 1000 }, 415],
    [{ purpose: 'lot', contentType: 'image/jpeg', size: 5 * 1024 * 1024 + 1 }, 413],
    [{ purpose: 'lot', contentType: 'image/jpeg', size: 0 }, 400],
    [{ purpose: 'lot', contentType: 'image/jpeg', size: '1000' }, 400],
    [{ purpose: 'lot', contentType: 'image/jpeg', size: 1.5 }, 400],
    [{ purpose: 'documentos', contentType: 'image/jpeg', size: 1000 }, 400],
    [{ purpose: '__proto__', contentType: 'image/jpeg', size: 1000 }, 400],
    [{ contentType: 'image/jpeg', size: 1000 }, 400],
  ];
  for (const [cuerpo, estado] of casos) {
    assert.equal((await pedir({ cuerpo })).status, estado, JSON.stringify(cuerpo));
  }
});

test('acepta exactamente 5 MB y los tres formatos permitidos', async () => {
  for (const [tipo, ext] of [['image/jpeg', 'jpg'], ['image/png', 'png'], ['image/webp', 'webp']]) {
    const r = await pedir({ cuerpo: { purpose: 'lot', contentType: tipo, size: 5 * 1024 * 1024 } });
    assert.equal(r.status, 200, tipo);
    assert.ok((await r.json()).fileName.endsWith(`.${ext}`));
  }
});

test('rechaza cuerpos que no son JSON, no son objeto o son enormes', async () => {
  const base = (body) => handle(
    new Request('https://w.example.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${tokenValido}` }, body }),
    ENV, { fetch: fetchFalso, nowMs: NOW_MS });
  const tokenValido = await firmar(claveGoogle.privada, 'kid-1', payloadBase());
  assert.equal((await base('no es json')).status, 400);
  assert.equal((await base('[1,2]')).status, 400);
  assert.equal((await base('null')).status, 400);
  assert.equal((await base(JSON.stringify({ purpose: 'lot', x: 'a'.repeat(3000) }))).status, 413);
});

test('solo acepta POST en la raíz', async () => {
  assert.equal((await pedir({ metodo: 'GET' })).status, 405);
  assert.equal((await pedir({ url: 'https://w.example.workers.dev/otra' })).status, 404);
});

test('exige HTTPS salvo ALLOW_HTTP en desarrollo local', async () => {
  assert.equal((await pedir({ url: 'http://w.example.workers.dev/' })).status, 400);
  assert.equal((await pedir({ url: 'http://localhost:8787/', env: { ...ENV, ALLOW_HTTP: 'true' } })).status, 200);
});

test('sin configuración completa responde 500 sin revelar nada', async () => {
  const { IMAGEKIT_PRIVATE_KEY, ...sinClave } = ENV;
  const r = await pedir({ env: sinClave });
  assert.equal(r.status, 500);
  assert.ok(!(await r.text()).includes('IMAGEKIT'));
});

test('frena a un usuario que pide demasiadas autorizaciones (429)', async () => {
  let ultimo;
  for (let i = 0; i < 31; i++) ultimo = await pedir();
  assert.equal(ultimo.status, 429);
});

test('un fallo de red al pedir las claves de Firebase responde 503, no 401', async () => {
  const roto = () => Promise.resolve(new Response('x', { status: 500 }));
  const t = await firmar(claveGoogle.privada, 'kid-1', payloadBase());
  const r = await handle(
    new Request('https://w.example.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${t}` }, body: '{}' }),
    ENV, { fetch: roto, nowMs: NOW_MS });
  assert.equal(r.status, 503);
});
