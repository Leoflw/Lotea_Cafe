// Causa del 503 observado en producción: `fetchConCuenta` llamaba al fetch global como método de un
// objeto (`deps.fetchFn(...)`). En Cloudflare Workers eso lanza «Illegal invocation»; el registro v1
// mostraba etapa firestore_listar_dispositivos + causa «red» porque esa fue la primera llamada que
// pasó por ahí (OAuth y las lecturas como usuario usan llamadas simples y funcionaban).
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { listarDispositivos } from '../src/firestore.js';
import { ENDPOINT, NOW_MS, PROJECT, VENDEDOR, fetchEstricto, mundoDeChat, mundoDeCotizacion } from './_helpers.js';
import { CHAT, COT, pedir } from './_pedir.js';
import { ENTRADA, EN_DISPOSITIVOS, correr, errorDe, googleError, lanzarEn, sinSecretos } from './_diag.js';

// ------------------------------------------------------------------ el emulador es fiel a lo documentado
test('el fetch estricto emula Workers: falla como método de otro objeto y funciona como función simple', async () => {
  const f = fetchEstricto(async () => 'ok');
  assert.equal(await f(), 'ok'); // llamada simple
  const objeto = { f };
  assert.throws(() => objeto.f(), { name: 'TypeError', message: /Illegal invocation/ }); // como método
});

// ------------------------------------------------------------------ REGRESIÓN de la causa
test('REGRESIÓN: con un fetch que exige `this` correcto el aviso se envía (listar dispositivos, deduplicación y FCM)', async () => {
  const w = await mundoDeChat();
  const logs = [];
  const r = await pedir(w, { token: await w.idToken(), fetch: fetchEstricto(w.fetch), log: (e) => logs.push(e) });
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.estado, 'enviado');
  assert.equal(r.cuerpo.enviados, 1);
  assert.equal(w.enviados.length, 1);
  assert.equal(errorDe(logs), undefined);
  assert.equal(w.dedupe()[0][1].fields.estado.stringValue, 'enviado');
});

test('REGRESIÓN: cotizaciones con fetch estricto también se envían a ambas partes', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'solicitudCreada' });
  const r = await pedir(w, { cuerpo: COT('e1'), fetch: fetchEstricto(w.fetch) });
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.estado, 'enviado');
});

test('REGRESIÓN: sin fetch inyectado, el Worker usa el fetch GLOBAL sin `this` ajeno (ruta real de producción)', async () => {
  const w = await mundoDeChat();
  const original = globalThis.fetch;
  globalThis.fetch = fetchEstricto(w.fetch);
  try {
    const req = new Request(ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await w.idToken()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(CHAT()),
    });
    const resp = await handle(req, w.env, { nowMs: NOW_MS, log: () => {} }); // sin deps.fetch, como en Workers
    assert.equal(resp.status, 200);
    assert.equal((await resp.json()).estado, 'enviado');
    assert.equal(w.enviados.length, 1);
  } finally {
    globalThis.fetch = original;
  }
});

test('la URL REST de «listar tokens» es exacta y la petición autenticada está bien formada', async () => {
  const w = await mundoDeChat();
  const llamadas = [];
  const espia = async (url, init) => {
    llamadas.push({ url: String(url), init });
    return w.fetch(url, init);
  };
  // Primero un access token real del mundo simulado, usando la misma ruta que el Worker.
  const dispositivos = await listarDispositivos(w.env, PROJECT, VENDEDOR, { fetchFn: espia, nowMs: NOW_MS });
  assert.equal(dispositivos.length, 1);
  const lista = llamadas.find((c) => c.url.includes('/deviceTokens'));
  // Formato oficial: GET https://firestore.googleapis.com/v1/{parent=projects/*/databases/*/documents/*/**}/{collectionId}
  assert.equal(lista.url, `https://firestore.googleapis.com/v1/projects/lotea-cafe/databases/(default)/documents/users/${VENDEDOR}/deviceTokens?pageSize=20`);
  assert.equal(lista.init.method, 'GET');
  assert.equal(lista.init.body, undefined); // un GET no lleva cuerpo
  assert.match(lista.init.headers.Authorization, /^Bearer \S+$/);
});

// ------------------------------------------------------------------ excepciones de transporte
const TRANSPORTE = [
  ['TypeError «Illegal invocation»', () => new TypeError('Illegal invocation: function called with incorrect `this` reference. See https://developers.cloudflare.com/…'), 'TypeError', 'invocacion_ilegal'],
  ['DOMException AbortError', () => new DOMException('The operation was aborted. SECRETO', 'AbortError'), 'DOMException', 'abortado'],
  ['DOMException TimeoutError', () => new DOMException('timeout SECRETO', 'TimeoutError'), 'DOMException', 'timeout'],
  ['TypeError con causa ECONNRESET (undici)', () => Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('RED-CAIDA-SECRETO'), { code: 'ECONNRESET' }) }), 'TypeError', 'ECONNRESET'],
  ['Error «Network connection lost»', () => new Error('Network connection lost.'), 'Error', 'conexion_perdida'],
  ['TypeError «Too many subrequests»', () => new TypeError('Too many subrequests by single Worker invocation.'), 'TypeError', 'limite_subpeticiones'],
  ['TypeError sin patrón conocido', () => new TypeError('RED-CAIDA-SECRETO inclasificable'), 'TypeError', 'sin_clasificar'],
  ['clase, nombre y código hostiles', () => Object.assign(new (class SECRETO extends Error {})('SECRETO'), { name: 'SECRETO', code: 'SECRETO-CODE' }), 'otro', 'sin_clasificar'],
];
for (const [nombre, fabricar, errorNombre, errorCodigo] of TRANSPORTE) {
  test(`transporte al listar dispositivos — ${nombre}: causa «red», clase «${errorNombre}», código «${errorCodigo}»`, async () => {
    const w = await mundoDeChat();
    lanzarEn(w, EN_DISPOSITIVOS, fabricar());
    const { status, cuerpo, logs, token } = await correr(w);
    assert.equal(status, 503); // tratamiento conservado
    assert.deepEqual(cuerpo, ENTRADA);
    assert.deepEqual(errorDe(logs), {
      evento: 'notify_error', clase: 'upstream', etapa: 'firestore_listar_dispositivos', servicio: 'firestore',
      causa: 'red', errorNombre, errorCodigo, tipo: 'chatMessage',
    });
    assert.equal(w.enviados.length, 0);
    sinSecretos(w, logs, token, ['SECRETO', 'Illegal', 'incorrect', 'aborted', 'inclasificable', 'fetch failed', 'subrequests']);
  });
}

// ------------------------------------------------------------------ respuestas HTTP (NO son excepciones de transporte)
for (const [http, googleStatus] of [[401, 'UNAUTHENTICATED'], [403, 'PERMISSION_DENIED'], [429, 'RESOURCE_EXHAUSTED'], [500, 'INTERNAL'], [503, 'UNAVAILABLE']]) {
  test(`HTTP ${http} de Firestore al listar dispositivos: causa «http», sin clase ni código de excepción`, async () => {
    const w = await mundoDeChat();
    w.fallosFirestore.push({ metodo: 'GET', quien: 'cuenta', ruta: /\/deviceTokens$/, respuesta: () => googleError(http, googleStatus) });
    const { status, cuerpo, logs, token } = await correr(w);
    assert.equal(status, 503);
    assert.deepEqual(cuerpo, ENTRADA);
    assert.deepEqual(errorDe(logs), {
      evento: 'notify_error', clase: 'upstream', etapa: 'firestore_listar_dispositivos', servicio: 'firestore',
      causa: 'http', http, googleStatus, tipo: 'chatMessage',
    });
    if (http === 401) assert.equal(w.llamadasOauth, 2, 'ante un 401 se renueva el token UNA vez y se reintenta');
    sinSecretos(w, logs, token);
  });
}

// ------------------------------------------------------------------ otras etapas con la misma captura
test('excepción de transporte en OAuth: etapa oauth_token con clase y código', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /oauth2\.googleapis\.com/, new TypeError('Illegal invocation: function called with incorrect `this` reference.'));
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  const e = errorDe(logs);
  assert.deepEqual({ et: e.etapa, op: e.operacion, c: e.causa, n: e.errorNombre, k: e.errorCodigo }, { et: 'oauth_token', op: 'firestore_listar_dispositivos', c: 'red', n: 'TypeError', k: 'invocacion_ilegal' });
  sinSecretos(w, logs, token, ['Illegal']);
});

test('excepción de transporte en la lectura como usuario: etapa firestore_leer_evento con clase y código', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /interestRequests/, new DOMException('x SECRETO', 'AbortError'));
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  const e = errorDe(logs);
  assert.deepEqual({ et: e.etapa, o: e.objeto, n: e.errorNombre, k: e.errorCodigo }, { et: 'firestore_leer_evento', o: 'conexion', n: 'DOMException', k: 'abortado' });
  sinSecretos(w, logs, token, ['SECRETO']);
});

test('excepción de transporte en la deduplicación: operación firestore_dedupe_crear', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /pushDedupe/, new TypeError('RED-CAIDA-SECRETO'));
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ et: errorDe(logs).etapa, c: errorDe(logs).causa, k: errorDe(logs).errorCodigo }, { et: 'firestore_dedupe_crear', c: 'red', k: 'sin_clasificar' });
  sinSecretos(w, logs, token);
});

test('excepción de transporte hacia FCM: fcm_fallo con clase y código, sin atribuirlo a OAuth ni Firestore', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /fcm\.googleapis\.com/, new Error('Network connection lost.'));
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.equal(errorDe(logs), undefined);
  const f = logs.find((l) => l.evento === 'fcm_fallo');
  assert.deepEqual(
    { r: f.resultado, et: f.etapa, s: f.servicio, c: f.causa, n: f.errorNombre, k: f.errorCodigo },
    { r: 'transitorio', et: 'fcm_enviar', s: 'fcm', c: 'red', n: 'Error', k: 'conexion_perdida' },
  );
  sinSecretos(w, logs, token);
});

test('claves públicas de Firebase: excepción de transporte con clase y código', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /www\.googleapis\.com/, new TypeError('RED-CAIDA-SECRETO'));
  const { status, logs } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ et: errorDe(logs).etapa, k: errorDe(logs).errorCodigo }, { et: 'verificar_id_token', k: 'sin_clasificar' });
});
