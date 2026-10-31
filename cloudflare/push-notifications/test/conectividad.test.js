// GET /diagnostico: comprobación de conectividad autenticada, opcional y solo de lectura.
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { DIAGNOSTICO_TOKEN_MIN, diagnosticoActivo, tokenCorrecto } from '../src/conectividad.js';
import { NOW_MS, fetchEstricto, mundoDeChat } from './_helpers.js';
import { googleError, json, lanzarEn, sinSecretos } from './_diag.js';

const URL_DIAG = 'https://push.example.workers.dev/diagnostico';
const TOKEN = `diag-${'x'.repeat(30)}`;
const ID_TOKEN_FICTICIO = 'cabecera-ficticia.carga-ficticia.firma-ficticia-inexistente'; // el Worker no usa ID token aquí

async function pedirDiag(w, { token = TOKEN, metodo = 'GET', env, fetch } = {}) {
  const logs = [];
  const headers = token === null ? {} : { Authorization: `Bearer ${token}` };
  const resp = await handle(new Request(URL_DIAG, { method: metodo, headers }), env ?? { ...w.env, DIAGNOSTICO_TOKEN: TOKEN }, {
    fetch: fetch ?? w.fetch, nowMs: NOW_MS, log: (e) => logs.push(e),
  });
  const texto = await resp.text();
  return { status: resp.status, texto, cuerpo: JSON.parse(texto), logs };
}
const paso = (r, nombre) => r.cuerpo.pasos.find((p) => p.paso === nombre);

test('desactivada por defecto: sin DIAGNOSTICO_TOKEN todo responde como antes (GET 405, POST 404)', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedirDiag(w, { env: w.env })).status, 405);
  assert.equal((await pedirDiag(w, { env: w.env, token: null })).status, 405);
  assert.equal((await pedirDiag(w, { metodo: 'POST' })).status, 404);
});

test('un token demasiado corto no activa la ruta', async () => {
  const w = await mundoDeChat();
  const corto = 'x'.repeat(DIAGNOSTICO_TOKEN_MIN - 1);
  assert.equal(diagnosticoActivo({ DIAGNOSTICO_TOKEN: corto }), false);
  assert.equal((await pedirDiag(w, { env: { ...w.env, DIAGNOSTICO_TOKEN: corto }, token: corto })).status, 405);
});

test('con token ausente o incorrecto responde 404 «No encontrado.» sin tocar Google', async () => {
  const w = await mundoDeChat();
  for (const token of [null, 'otro-token-distinto-de-32-caracteres!!', `${TOKEN}x`, '']) {
    const r = await pedirDiag(w, { token });
    assert.equal(r.status, 404);
    assert.deepEqual(r.cuerpo, { error: 'No encontrado.' });
  }
  assert.equal(w.accesos.length, 0);
  assert.equal(w.llamadasOauth, 0);
});

test('tokenCorrecto compara en tiempo constante y distingue valores', async () => {
  assert.equal(await tokenCorrecto(TOKEN, TOKEN), true);
  assert.equal(await tokenCorrecto(TOKEN, `${TOKEN}.`), false);
  assert.equal(await tokenCorrecto('', TOKEN), false);
});

test('correcto: tres pasos «ok», solo lecturas, un documento fijo y NADA de usuarios', async () => {
  const w = await mundoDeChat();
  const antes = JSON.stringify([...w.docs.entries()]);
  const r = await pedirDiag(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.ok, true);
  assert.deepEqual(r.cuerpo.pasos.map((p) => [p.paso, p.resultado]), [['salida_publica', 'ok'], ['oauth', 'ok'], ['firestore_autenticado', 'ok']]);
  assert.equal(paso(r, 'firestore_autenticado').http, 404); // el documento fijo no existe: 404 autenticado = correcto
  // Solo una lectura con la cuenta de servicio, sobre el documento fijo; sin escrituras ni FCM.
  assert.deepEqual(w.accesos, [{ metodo: 'GET', ruta: 'pushDedupe/diagnostico-conectividad', quien: 'cuenta' }]);
  assert.equal(JSON.stringify([...w.docs.entries()]), antes);
  assert.equal(w.enviados.length, 0);
  sinSecretos(w, r.texto, ID_TOKEN_FICTICIO);
  sinSecretos(w, r.logs, ID_TOKEN_FICTICIO);
});

test('con un fetch que exige `this` correcto la comprobación pasa (usa la misma ruta que /notify)', async () => {
  const w = await mundoDeChat();
  const r = await pedirDiag(w, { fetch: fetchEstricto(w.fetch) });
  assert.equal(r.cuerpo.ok, true);
});

test('Firestore autenticado 403: el paso falla con HTTP y código permitido; OAuth y salida pública siguen «ok»', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({ metodo: 'GET', quien: 'cuenta', ruta: /^pushDedupe\/diagnostico-conectividad$/, respuesta: () => googleError(403, 'PERMISSION_DENIED') });
  const r = await pedirDiag(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.ok, false);
  assert.equal(paso(r, 'salida_publica').resultado, 'ok');
  assert.equal(paso(r, 'oauth').resultado, 'ok');
  assert.deepEqual(paso(r, 'firestore_autenticado'), {
    paso: 'firestore_autenticado', resultado: 'fallo', etapa: 'diagnostico_firestore', servicio: 'firestore', causa: 'http', http: 403, googleStatus: 'PERMISSION_DENIED',
  });
  sinSecretos(w, r.texto, ID_TOKEN_FICTICIO);
});

test('excepción de transporte en el paso autenticado: clase y código; la salida pública y OAuth siguen «ok»', async () => {
  const w = await mundoDeChat();
  lanzarEn(w, /firestore\.googleapis\.com/, new TypeError('Illegal invocation: function called with incorrect `this` reference.'));
  const r = await pedirDiag(w);
  assert.equal(r.cuerpo.ok, false);
  assert.deepEqual(
    { a: paso(r, 'salida_publica').resultado, b: paso(r, 'oauth').resultado, c: paso(r, 'firestore_autenticado') },
    { a: 'ok', b: 'ok', c: { paso: 'firestore_autenticado', resultado: 'fallo', etapa: 'diagnostico_firestore', servicio: 'firestore', causa: 'red', errorNombre: 'TypeError', errorCodigo: 'invocacion_ilegal' } },
  );
  sinSecretos(w, r.texto, ID_TOKEN_FICTICIO, ['Illegal']);
});

test('OAuth rechazado: el paso oauth falla con código OAuth permitido', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => json(400, { error: 'invalid_grant', error_description: 'HOSTIL-MENSAJE Invalid JWT Signature.' });
  const r = await pedirDiag(w);
  assert.equal(r.cuerpo.ok, false);
  assert.deepEqual({ r: paso(r, 'oauth').resultado, e: paso(r, 'oauth').oauthError, h: paso(r, 'oauth').http }, { r: 'fallo', e: 'invalid_grant', h: 400 });
  sinSecretos(w, r.texto, ID_TOKEN_FICTICIO);
});

test('sin salida a Internet: el primer paso lo dice y los demás también fallan por red', async () => {
  const w = await mundoDeChat();
  w.redCaida.add('www.googleapis.com');
  w.redCaida.add('oauth2.googleapis.com');
  const r = await pedirDiag(w);
  assert.equal(paso(r, 'salida_publica').causa, 'red');
  assert.equal(paso(r, 'oauth').causa, 'red');
});

test('un secreto de cuenta de servicio ilegible no se refleja en la respuesta', async () => {
  const w = await mundoDeChat();
  const r = await pedirDiag(w, { env: { ...w.env, DIAGNOSTICO_TOKEN: TOKEN, FCM_SERVICE_ACCOUNT_JSON: 'SECRETO-JSON-INVALIDO' } });
  assert.equal(paso(r, 'oauth').motivo, 'json_invalido');
  assert.equal(r.texto.includes('SECRETO'), false);
  assert.equal(JSON.stringify(r.logs).includes('SECRETO'), false);
});

test('POST /notify sigue funcionando igual con el secreto de diagnóstico activado', async () => {
  const w = await mundoDeChat();
  const { pedir } = await import('./_pedir.js');
  const r = await pedir(w, { env: { ...w.env, DIAGNOSTICO_TOKEN: TOKEN } });
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.estado, 'enviado');
});
