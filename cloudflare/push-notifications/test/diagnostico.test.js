// Diagnóstico: cada fallo identifica su ETAPA y su servicio (OAuth, Firestore o
// FCM) con el código HTTP y códigos de Google de una lista permitida; los
// códigos HTTP que recibe Flutter no cambian; y el registro NO revela nada privado.
import test from 'node:test';
import assert from 'node:assert/strict';
import { claveDeEvento, LEASE_MS } from '../src/dedupe.js';
import { ETAPAS, codigosDeGoogle, leerCuerpoError, nombreSeguro, sanear } from '../src/diagnostico.js';
import { ConfigError, UpstreamError } from '../src/errores.js';
import { construirMensaje, enviarDetallado } from '../src/fcm.js';
import { fetchConCuenta } from '../src/google-auth.js';
import { COMPRADOR, CONEXION, FCM, NOW_MS, VENDEDOR, mundoDeChat, mundoDeCotizacion, s } from './_helpers.js';
import { COT, pedir } from './_pedir.js';

const ENTRADA = { error: 'Servicio temporalmente no disponible. Puedes reintentar.', reintentable: true };
const json = (estado, cuerpo) => new Response(JSON.stringify(cuerpo), { status: estado, headers: { 'Content-Type': 'application/json' } });
const googleError = (estado, status, extra = {}) => json(estado, { error: { code: estado, status, message: status, ...extra } });

/** Respuesta de Google con TEXTO LIBRE hostil: nada de esto debe llegar al registro. */
const hostil = (estado, status, detalles = []) =>
  json(estado, {
    error: {
      code: estado,
      status,
      message: 'HOSTIL-MENSAJE Bearer ya29.TOKEN-OAUTH-SECRETO tokV1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx SECRETO-DEL-CHAT',
      details: [{ '@type': 'x', reason: 'RAZON-INVENTADA', extra: 'HOSTIL-DETALLE' }, ...detalles],
    },
  });

/** Ejecuta una petición y devuelve respuesta + registros. */
async function correr(w, opciones = {}) {
  const logs = [];
  const token = opciones.token ?? (await w.idToken());
  const r = await pedir(w, { ...opciones, token, log: (e) => logs.push(e) });
  return { ...r, logs, token };
}
const error = (logs) => logs.find((l) => l.evento === 'notify_error');

/** Afirma que ningún registro contiene datos privados ni texto libre de Google. */
function sinSecretos(w, logs, token, extras = []) {
  const texto = JSON.stringify(logs);
  const sa = JSON.parse(w.sa.json);
  const cuerpoClave = sa.private_key.replace(/-----[A-Z ]+-----|\s/g, '');
  const prohibidos = [
    'BEGIN PRIVATE KEY', cuerpoClave.slice(20, 60), sa.client_email, // cuenta de servicio
    token, token.split('.')[2], // ID token de Firebase (y su firma)
    'at_1', 'ya29', 'TOKEN-OAUTH-SECRETO', // tokens OAuth
    'tokV1', 'tokC', w.tokenValido('tokV1'), // tokens FCM (completos o parciales)
    'Bearer', 'Authorization', 'authorization', // cabeceras
    'SECRETO-DEL-CHAT', // contenido del chat
    'HOSTIL-MENSAJE', 'HOSTIL-DETALLE', 'RAZON-INVENTADA', 'RED-CAIDA-SECRETO', // texto libre de Google o de errores de red
    COMPRADOR, VENDEDOR, CONEXION, // identificadores de personas y conversaciones
    ...extras,
  ];
  for (const p of prohibidos) assert.equal(texto.includes(p), false, `el registro contiene «${p}»: ${texto}`);
}

// ---------------------------------------------------------------- OAuth
test('OAuth 503: etapa oauth_token, servicio oauth, HTTP 503; Flutter sigue recibiendo 503 reintentable', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => googleError(503, 'UNAVAILABLE');
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual(cuerpo, ENTRADA);
  assert.deepEqual(error(logs), {
    evento: 'notify_error', clase: 'upstream', etapa: 'oauth_token', operacion: 'firestore_listar_dispositivos',
    servicio: 'oauth', causa: 'http', http: 503, googleStatus: 'UNAVAILABLE', tipo: 'chatMessage',
  });
  assert.equal(w.enviados.length, 0);
  sinSecretos(w, logs, token);
});

test('OAuth 429 con un código `error` fuera de la lista: se registra como «otro», no el texto', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => json(429, { error: 'HOSTIL-MENSAJE', error_description: 'HOSTIL-DETALLE assertion=eyJhbGciOi.SECRETO' });
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.equal(error(logs).etapa, 'oauth_token');
  assert.equal(error(logs).oauthError, 'otro');
  assert.equal(error(logs).http, 429);
  sinSecretos(w, logs, token, ['assertion', 'eyJhbGciOi']);
});

test('OAuth rechaza la cuenta (400 invalid_grant): clase config, 500 hacia Flutter, código OAuth permitido', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => json(400, { error: 'invalid_grant', error_description: 'HOSTIL-MENSAJE Invalid JWT Signature.' });
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 500);
  assert.deepEqual(cuerpo, { error: 'El Worker no está configurado correctamente.' });
  assert.deepEqual(error(logs), {
    evento: 'notify_error', clase: 'config', etapa: 'oauth_token', operacion: 'firestore_listar_dispositivos',
    servicio: 'oauth', causa: 'http', http: 400, oauthError: 'invalid_grant', motivo: 'oauth_rechazado', tipo: 'chatMessage',
  });
  sinSecretos(w, logs, token);
});

test('OAuth sin red: causa «red», sin el mensaje de la excepción', async () => {
  const w = await mundoDeChat();
  w.redCaida.add('oauth2.googleapis.com');
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual(
    { e: error(logs).etapa, s: error(logs).servicio, c: error(logs).causa, h: error(logs).http },
    { e: 'oauth_token', s: 'oauth', c: 'red', h: undefined },
  );
  sinSecretos(w, logs, token);
});

test('OAuth responde 200 sin access_token: causa respuesta_invalida', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => json(200, { token_type: 'Bearer' });
  const { status, logs } = await correr(w);
  assert.equal(status, 503);
  assert.equal(error(logs).causa, 'respuesta_invalida');
  assert.equal(error(logs).etapa, 'oauth_token');
});

for (const [nombre, secreto, motivo] of [
  ['no es JSON', 'SECRETO-JSON-INVALIDO-xyz', 'json_invalido'],
  ['es JSON pero no un objeto', '"SECRETO-TEXTO"', 'no_es_objeto'],
  ['sin client_email', JSON.stringify({ project_id: 'lotea-cafe', private_key: '-----BEGIN PRIVATE KEY-----\nSECRETO\n-----END PRIVATE KEY-----' }), 'sin_client_email'],
  ['sin clave privada', JSON.stringify({ project_id: 'lotea-cafe', client_email: 'a@b.iam' }), 'sin_clave_privada'],
  ['de otro proyecto', JSON.stringify({ project_id: 'otro', client_email: 'a@b.iam', private_key: '-----BEGIN PRIVATE KEY-----\nSECRETO\n-----END PRIVATE KEY-----' }), 'proyecto_distinto'],
  ['con clave ilegible', JSON.stringify({ project_id: 'lotea-cafe', client_email: 'a@b.iam', private_key: '-----BEGIN PRIVATE KEY-----\nSECRETO\n-----END PRIVATE KEY-----' }), 'clave_ilegible'],
]) {
  test(`secreto FCM_SERVICE_ACCOUNT_JSON ${nombre}: etapa oauth_cuenta_servicio, motivo «${motivo}», 500 y sin contenido del secreto`, async () => {
    const w = await mundoDeChat();
    const { status, cuerpo, logs, token } = await correr(w, { env: { ...w.env, FCM_SERVICE_ACCOUNT_JSON: secreto } });
    assert.equal(status, 500);
    assert.deepEqual(cuerpo, { error: 'El Worker no está configurado correctamente.' });
    assert.equal(error(logs).clase, 'config');
    assert.equal(error(logs).etapa, 'oauth_cuenta_servicio');
    assert.equal(error(logs).motivo, motivo);
    sinSecretos(w, logs, token, ['SECRETO', 'a@b.iam', 'lotea-cafe.iam']);
  });
}

test('OAuth caído al enviar a FCM: el envío es «transitorio» y el diagnóstico indica OAuth (no FCM)', async () => {
  const w = await mundoDeChat();
  w.fallosOauth = () => googleError(503, 'UNAVAILABLE');
  const mensaje = construirMensaje({ token: w.tokenValido('tokV1'), ruta: 'chat', id: 'x', canal: 'c' });
  const r = await enviarDetallado(w.env, 'lotea-cafe', mensaje, { fetchFn: w.fetch, nowMs: NOW_MS });
  assert.equal(r.resultado, 'transitorio');
  assert.deepEqual(r.diag, { etapa: 'oauth_token', operacion: 'fcm_enviar', servicio: 'oauth', causa: 'http', http: 503, googleStatus: 'UNAVAILABLE' });
  await assert.rejects(
    fetchConCuenta(w.env, 'https://fcm.googleapis.com/x', { method: 'POST' }, { fetchFn: w.fetch, nowMs: NOW_MS }, 'fcm_enviar'),
    (e) => e instanceof UpstreamError && e.diag.operacion === 'fcm_enviar',
  );
});

// ---------------------------------------------------------------- Firestore
test('Firestore (lectura como usuario) 500: etapa firestore_leer_evento, objeto «conexion», HTTP 500 e INTERNAL', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({ metodo: 'GET', quien: 'usuario', ruta: /^interestRequests\//, respuesta: () => hostil(500, 'INTERNAL') });
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual(cuerpo, ENTRADA);
  assert.deepEqual(error(logs), {
    evento: 'notify_error', clase: 'upstream', etapa: 'firestore_leer_evento', servicio: 'firestore', causa: 'http',
    http: 500, googleStatus: 'INTERNAL', googleRazon: 'otro', objeto: 'conexion', tipo: 'chatMessage',
  });
  assert.equal(w.enviados.length, 0);
  sinSecretos(w, logs, token);
});

test('Firestore (lectura como usuario) identifica el documento que falló: mensaje, cotización y evento', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({ metodo: 'GET', quien: 'usuario', ruta: /\/messages\//, respuesta: () => googleError(400, 'INVALID_ARGUMENT') });
  let r = await correr(w);
  assert.equal(error(r.logs).objeto, 'mensaje');
  assert.equal(error(r.logs).googleStatus, 'INVALID_ARGUMENT');

  const c = await mundoDeCotizacion();
  c.ponerEvento('e1');
  c.fallosFirestore.push({ metodo: 'GET', quien: 'usuario', ruta: /^quotes\/q1$/, respuesta: () => googleError(500, 'INTERNAL') });
  r = await correr(c, { cuerpo: COT('e1') });
  assert.equal(error(r.logs).objeto, 'cotizacion');
  assert.equal(error(r.logs).tipo, 'quoteEvent');

  const d = await mundoDeCotizacion();
  d.ponerEvento('e1');
  d.fallosFirestore.push({ metodo: 'GET', quien: 'usuario', ruta: /\/events\//, respuesta: () => googleError(500, 'INTERNAL') });
  r = await correr(d, { cuerpo: COT('e1') });
  assert.equal(error(r.logs).objeto, 'evento');
});

test('Firestore sin red al leer como usuario: causa «red»', async () => {
  const w = await mundoDeChat();
  w.redCaida.add('firestore.googleapis.com');
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ e: error(logs).etapa, c: error(logs).causa, o: error(logs).objeto }, { e: 'firestore_leer_evento', c: 'red', o: 'conexion' });
  sinSecretos(w, logs, token);
});

test('Firestore (tokens del destinatario) 403 PERMISSION_DENIED con razón SERVICE_DISABLED: etapa firestore_listar_dispositivos', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({
    metodo: 'GET', quien: 'cuenta', ruta: /\/deviceTokens$/,
    respuesta: () => hostil(403, 'PERMISSION_DENIED', [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: 'SERVICE_DISABLED' }]),
  });
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503); // se conserva el tratamiento actual
  assert.deepEqual(cuerpo, ENTRADA);
  assert.deepEqual(error(logs), {
    evento: 'notify_error', clase: 'upstream', etapa: 'firestore_listar_dispositivos', servicio: 'firestore', causa: 'http',
    http: 403, googleStatus: 'PERMISSION_DENIED', googleRazon: 'SERVICE_DISABLED', tipo: 'chatMessage',
  });
  assert.equal(w.enviados.length, 0);
  assert.equal(w.dedupe().length, 0); // no se llegó a la deduplicación
  sinSecretos(w, logs, token);
});

test('Firestore (tokens del destinatario) sin red: causa «red» y operación firestore_listar_dispositivos', async () => {
  const w = await mundoDeChat();
  // Solo cae la llamada con cuenta de servicio: la de lectura como usuario ya pasó.
  let primera = true;
  const base = w.fetch;
  w.fetch = async (url, init) => {
    const u = new URL(String(url));
    if (u.hostname === 'firestore.googleapis.com' && u.pathname.endsWith('/deviceTokens')) throw new TypeError('fetch failed: RED-CAIDA-SECRETO');
    primera = false;
    return base(url, init);
  };
  const { status, logs, token } = await correr(w);
  assert.equal(primera, false);
  assert.equal(status, 503);
  assert.deepEqual(
    { e: error(logs).etapa, c: error(logs).causa, s: error(logs).servicio },
    { e: 'firestore_listar_dispositivos', c: 'red', s: 'firestore' },
  );
  sinSecretos(w, logs, token);
});

test('Deduplicación: error al crear el registro → etapa firestore_dedupe_crear', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({ metodo: 'POST', quien: 'cuenta', ruta: /^pushDedupe$/, respuesta: () => hostil(403, 'PERMISSION_DENIED') });
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual(cuerpo, ENTRADA);
  assert.deepEqual(
    { e: error(logs).etapa, h: error(logs).http, g: error(logs).googleStatus, s: error(logs).servicio },
    { e: 'firestore_dedupe_crear', h: 403, g: 'PERMISSION_DENIED', s: 'firestore' },
  );
  assert.equal(w.enviados.length, 0);
  sinSecretos(w, logs, token);
});

test('Deduplicación: error al leer un registro existente → etapa firestore_dedupe_leer', async () => {
  const w = await mundoDeChat();
  const id = await claveDeEvento('chatMessage', CONEXION, 'm1');
  w.poner(`pushDedupe/${id}`, { estado: s('enviando'), claimedAtMs: { integerValue: String(NOW_MS) } });
  w.fallosFirestore.push({ metodo: 'GET', quien: 'cuenta', ruta: /^pushDedupe\//, respuesta: () => googleError(500, 'INTERNAL') });
  const { status, logs } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ e: error(logs).etapa, h: error(logs).http, g: error(logs).googleStatus }, { e: 'firestore_dedupe_leer', h: 500, g: 'INTERNAL' });
});

test('Deduplicación: error al tomar el relevo de un intento a medias → etapa firestore_dedupe_relevo', async () => {
  const w = await mundoDeChat();
  const id = await claveDeEvento('chatMessage', CONEXION, 'm1');
  w.poner(`pushDedupe/${id}`, { estado: s('enviando'), claimedAtMs: { integerValue: String(NOW_MS - LEASE_MS - 1000) } });
  w.fallosFirestore.push({ metodo: 'PATCH', quien: 'cuenta', ruta: /^pushDedupe\//, respuesta: () => googleError(500, 'INTERNAL') });
  const { status, logs } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ e: error(logs).etapa, h: error(logs).http }, { e: 'firestore_dedupe_relevo', h: 500 });
});

// ---------------------------------------------------------------- FCM
test('FCM 503: NO produce notify_error/upstream; se registra fcm_fallo en la etapa fcm_enviar y Flutter recibe 503', async () => {
  const w = await mundoDeChat();
  w.respuestaFcmPorDefecto = () => hostil(503, 'UNAVAILABLE');
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.equal(cuerpo.reintentable, true);
  assert.equal(error(logs), undefined, 'un fallo de FCM nunca genera «notify_error»: enviar() lo traduce a «transitorio»');
  assert.deepEqual(logs.find((l) => l.evento === 'fcm_fallo'), {
    evento: 'fcm_fallo', tipo: 'chatMessage', dispositivo: 1, resultado: 'transitorio',
    etapa: 'fcm_enviar', servicio: 'fcm', causa: 'http', http: 503, googleStatus: 'UNAVAILABLE', googleRazon: 'otro',
  });
  assert.equal(logs.find((l) => l.evento === 'notify').transitorios, 1);
  sinSecretos(w, logs, token);
});

test('FCM 403 SENDER_ID_MISMATCH: resultado «configuracion» (502), con código FCM permitido', async () => {
  const w = await mundoDeChat();
  w.respuestaFcmPorDefecto = () => hostil(403, 'PERMISSION_DENIED', [{ errorCode: 'SENDER_ID_MISMATCH' }]);
  const { status, logs, token } = await correr(w);
  assert.equal(status, 502);
  assert.deepEqual(logs.find((l) => l.evento === 'fcm_fallo'), {
    evento: 'fcm_fallo', tipo: 'chatMessage', dispositivo: 1, resultado: 'configuracion',
    etapa: 'fcm_enviar', servicio: 'fcm', causa: 'http', http: 403, googleStatus: 'PERMISSION_DENIED', googleRazon: 'otro', fcmCodigo: 'SENDER_ID_MISMATCH',
  });
  sinSecretos(w, logs, token);
});

test('FCM 404 UNREGISTERED: se registra tokenInvalido y se conserva el borrado del token', async () => {
  const w = await mundoDeChat();
  w.respuestaFcmPorDefecto = FCM.noRegistrado;
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 200);
  assert.equal(cuerpo.tokensEliminados, 1);
  const f = logs.find((l) => l.evento === 'fcm_fallo');
  assert.deepEqual({ r: f.resultado, h: f.http, c: f.fcmCodigo }, { r: 'tokenInvalido', h: 404, c: 'UNREGISTERED' });
  assert.equal(w.dispositivos(VENDEDOR).length, 0);
  sinSecretos(w, logs, token);
});

test('FCM sin red: causa «red» en la etapa fcm_enviar', async () => {
  const w = await mundoDeChat();
  w.respuestaFcmPorDefecto = () => new TypeError('fetch failed: RED-CAIDA-SECRETO');
  const { status, logs, token } = await correr(w);
  assert.equal(status, 503);
  const f = logs.find((l) => l.evento === 'fcm_fallo');
  assert.deepEqual({ e: f.etapa, c: f.causa, s: f.servicio }, { e: 'fcm_enviar', c: 'red', s: 'fcm' });
  sinSecretos(w, logs, token);
});

test('FCM con 200 no genera ningún registro de error', async () => {
  const w = await mundoDeChat();
  const { status, logs } = await correr(w);
  assert.equal(status, 200);
  assert.deepEqual(logs.map((l) => l.evento), ['notify']);
});

// ---------------------------------------------------------------- Otras etapas
test('Claves públicas de Firebase caídas (500): etapa verificar_id_token, 503 como antes', async () => {
  const w = await mundoDeChat();
  w.jwksFallo = () => googleError(500, 'INTERNAL');
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual(cuerpo, { error: 'No se pudo validar la sesión. Inténtalo de nuevo.' });
  assert.deepEqual(error(logs), { evento: 'notify_error', clase: 'upstream', etapa: 'verificar_id_token', servicio: 'firebase_auth', causa: 'http', http: 500, googleStatus: 'INTERNAL' });
  sinSecretos(w, logs, token);
});

test('Claves públicas de Firebase sin red: causa «red»', async () => {
  const w = await mundoDeChat();
  w.redCaida.add('www.googleapis.com');
  const { status, logs } = await correr(w);
  assert.equal(status, 503);
  assert.deepEqual({ e: error(logs).etapa, c: error(logs).causa }, { e: 'verificar_id_token', c: 'red' });
});

test('Error inesperado: 500 «Error interno.», con la etapa y solo el NOMBRE de la clase del error', async () => {
  const w = await mundoDeChat();
  w.fallosFirestore.push({ metodo: 'GET', quien: 'cuenta', ruta: /\/deviceTokens$/, respuesta: () => new Response('SECRETO-DEL-CHAT no es json', { status: 200 }) });
  const { status, cuerpo, logs, token } = await correr(w);
  assert.equal(status, 500);
  assert.deepEqual(cuerpo, { error: 'Error interno.' });
  assert.deepEqual(error(logs), { evento: 'notify_error', clase: 'inesperado', etapa: 'firestore_listar_dispositivos', tipoError: 'SyntaxError', tipo: 'chatMessage' });
  sinSecretos(w, logs, token);
});

test('Rechazos de la petición (4xx): se registra el código y la etapa, sin el motivo ni identificadores', async () => {
  const w = await mundoDeChat();
  w.ponerMensaje('m1', { senderId: VENDEDOR }); // el mensaje no es del usuario que avisa
  const { status, logs, token } = await correr(w);
  assert.equal(status, 403);
  assert.deepEqual(logs, [{ evento: 'notify_rechazo', http: 403, etapa: 'firestore_leer_evento', tipo: 'chatMessage' }]);
  sinSecretos(w, logs, token);
});

// ---------------------------------------------------------------- Privacidad (todo junto)
test('PRIVACIDAD: con respuestas de Google hostiles en todas las etapas, ningún registro revela datos privados', async () => {
  const escenarios = [
    (w) => { w.fallosOauth = () => json(503, { error: 'HOSTIL-MENSAJE', error_description: 'HOSTIL-DETALLE ya29.TOKEN-OAUTH-SECRETO' }); },
    (w) => { w.fallosOauth = () => json(400, { error: 'invalid_grant', error_description: 'HOSTIL-MENSAJE Bearer ya29.TOKEN-OAUTH-SECRETO' }); },
    (w) => { w.fallosFirestore.push({ metodo: 'GET', quien: 'usuario', ruta: /^interestRequests\//, respuesta: () => hostil(500, 'INTERNAL') }); },
    (w) => { w.fallosFirestore.push({ metodo: 'GET', quien: 'cuenta', ruta: /\/deviceTokens$/, respuesta: () => hostil(403, 'PERMISSION_DENIED') }); },
    (w) => { w.fallosFirestore.push({ metodo: 'POST', quien: 'cuenta', ruta: /^pushDedupe$/, respuesta: () => hostil(500, 'INTERNAL') }); },
    (w) => { w.respuestaFcmPorDefecto = () => hostil(503, 'UNAVAILABLE', [{ errorCode: 'QUOTA_EXCEEDED' }]); },
    (w) => { w.respuestaFcmPorDefecto = () => hostil(400, 'INVALID_ARGUMENT', [{ fieldViolations: [{ field: 'message.token', description: 'tokV1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' }] }]); },
    (w) => { w.redCaida.add('oauth2.googleapis.com'); },
    (w) => { w.redCaida.add('firestore.googleapis.com'); },
    (w) => { w.jwksFallo = () => hostil(500, 'INTERNAL'); },
  ];
  for (const preparar of escenarios) {
    const w = await mundoDeChat();
    preparar(w);
    const { logs, token } = await correr(w);
    assert.ok(logs.length > 0);
    sinSecretos(w, logs, token);
  }
});

// ---------------------------------------------------------------- Unidades de diagnostico.js
test('codigosDeGoogle solo devuelve códigos de la lista permitida; el resto es «otro»; el texto libre se descarta', () => {
  assert.deepEqual(codigosDeGoogle({ error: { status: 'PERMISSION_DENIED', message: 'SECRETO', details: [{ reason: 'SERVICE_DISABLED' }, { errorCode: 'UNREGISTERED' }] } }), {
    googleStatus: 'PERMISSION_DENIED', googleRazon: 'SERVICE_DISABLED', fcmCodigo: 'UNREGISTERED',
  });
  assert.deepEqual(codigosDeGoogle({ error: { status: 'HOSTIL <script>', details: [{ reason: 'tokV1_secreto' }, { errorCode: 'ya29.secreto' }] } }), {
    googleStatus: 'otro', googleRazon: 'otro', fcmCodigo: 'otro',
  });
  assert.deepEqual(codigosDeGoogle({ error: { details: [{ reason: 'DESCONOCIDA' }, { reason: 'SERVICE_DISABLED' }, { errorCode: 'XXX' }, { errorCode: 'UNREGISTERED' }] } }), {
    googleRazon: 'SERVICE_DISABLED', fcmCodigo: 'UNREGISTERED',
  });
  assert.deepEqual(codigosDeGoogle({ error: 'invalid_grant', error_description: 'SECRETO' }), { oauthError: 'invalid_grant' });
  assert.deepEqual(codigosDeGoogle({ error: 'cualquier-cosa-secreta' }), { oauthError: 'otro' });
  for (const raro of [null, undefined, 'texto', 42, [], { error: null }, { error: 7 }, { error: { details: 'x' } }]) assert.deepEqual(codigosDeGoogle(raro), {});
});

test('sanear descarta claves desconocidas y valores fuera de los conjuntos cerrados', () => {
  const r = sanear({
    etapa: 'oauth_token', servicio: 'oauth', causa: 'http', http: 403, token: 'SECRETO', private_key: 'SECRETO', mensaje: 'SECRETO',
    motivo: 'texto libre SECRETO', objeto: 'SECRETO', operacion: 'SECRETO', googleStatus: 'SECRETO', oauthError: 'SECRETO',
  });
  assert.deepEqual(r, { etapa: 'oauth_token', operacion: 'otra', servicio: 'oauth', causa: 'http', objeto: 'otro', motivo: 'otro', http: 403, googleStatus: 'otro', oauthError: 'otro' });
  assert.equal(JSON.stringify(r).includes('SECRETO'), false);
  assert.deepEqual(sanear({ etapa: 'inventada', http: 'cuatro-cero-tres' }), { etapa: 'otra' });
  assert.deepEqual(sanear({ http: 99 }), {});
  assert.deepEqual(sanear(null), {});
});

test('leerCuerpoError no lanza con cuerpos no JSON ni gigantes; nombreSeguro nunca devuelve el mensaje', async () => {
  assert.equal(await leerCuerpoError(new Response('no es json')), null);
  assert.equal(await leerCuerpoError(new Response(JSON.stringify({ x: 'a'.repeat(20_000) }))), null);
  assert.deepEqual(await leerCuerpoError(new Response('{"a":1}')), { a: 1 });
  assert.equal(nombreSeguro(new TypeError('SECRETO')), 'TypeError');
  const raro = new Error('SECRETO');
  raro.name = 'SECRETO-COMO-NOMBRE';
  assert.equal(nombreSeguro(raro), 'otro');
  assert.equal(nombreSeguro(null), 'otro');
});

test('los errores con diag conservan su clase y su mensaje (el código HTTP de Flutter depende de la clase)', () => {
  const u = new UpstreamError('m', { etapa: 'oauth_token' });
  const c = new ConfigError('m', { etapa: 'oauth_token' });
  assert.ok(u instanceof Error && c instanceof Error);
  assert.deepEqual([u.message, c.message, new UpstreamError('x').diag], ['m', 'm', null]);
  assert.ok(ETAPAS.has('oauth_token') && ETAPAS.has('fcm_enviar') && ETAPAS.has('firestore_listar_dispositivos'));
});
