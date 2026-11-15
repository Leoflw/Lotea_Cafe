// Pruebas de la política de fotos HISTÓRICAS (interestRequests.loteFoto y quotes.loteFoto) y
// de la eliminación completa de un lote. Todo simulado en memoria (sin red, sin ImageKit real).
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handle, barrido, resetLimitador, MAX_POR_EJECUCION } from '../src/index.js';
import { resetJwksCache } from '../src/firebase.js';
import { resetAuthCache } from '../src/google-auth.js';
import { esperaTrasIntento, RETENIDA_REVISION_MS } from '../src/cleanup.js';
import { LIMITE_HISTORICOS } from '../src/lotes.js';
import { ENV, NOW_MS, RAIZ, mundoConClaves, tokenDe } from './backend-falso.js';

const FID_VIEJA = '5f8a1c2b3d4e5f6a7b8c9d11';
const FID_ACTUAL = '5f8a1c2b3d4e5f6a7b8c9d12';
const FID_NUEVA = '5f8a1c2b3d4e5f6a7b8c9d13';
const rutaImg = (uid, nombre) => `${RAIZ}/users/${uid}/lots/${nombre}`;
const cola = (uid, id) => `users/${uid}/pendingFileDeletions/${id}`;
const colaLote = (uid, id) => `users/${uid}/pendingLotDeletions/${id}`;
const DIA = 24 * 60 * 60 * 1000;

beforeEach(() => {
  resetLimitador();
  resetJwksCache();
  resetAuthCache();
});

async function envConCuenta() {
  const par = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', par.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return { ...ENV, CLEANUP_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'limpieza@lotea-cafe.iam.gserviceaccount.com', private_key: pem, project_id: 'lotea-cafe' }) };
}
const ENVR = await envConCuenta();

async function llamar(m, uid, nowMs = NOW_MS) {
  resetLimitador();
  const t = await tokenDe(m, uid, nowMs);
  const r = await handle(new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${t}` } }), ENVR, { fetch: m.fetch, nowMs });
  return r.json();
}
const cron = (m, nowMs = NOW_MS) => barrido(ENVR, { fetch: m.fetch, nowMs });

/** Mundo con un lote de ana y una foto suya en ImageKit. */
async function escenario() {
  const m = await mundoConClaves();
  resetJwksCache();
  for (const [fid, nombre] of [[FID_VIEJA, 'vieja.jpg'], [FID_ACTUAL, 'actual.jpg'], [FID_NUEVA, 'nueva.jpg']]) m.archivo(fid, rutaImg('ana', nombre));
  m.url = (fid) => m.archivos.get(fid).url;
  return m;
}
const escriturasA = (m, prefijo) => m.escrituras.filter((e) => e.ruta.startsWith(prefijo));

// ---------- 1-3. Una foto usada por el historial NO se borra ----------

test('1. una foto referenciada por una solicitud de interés NO se elimina: queda «retenida»', async () => {
  const m = await escenario();
  m.poner('interestRequests/c1_lote1', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.cola('ana', FID_VIEJA);
  const r = await llamar(m, 'ana');
  assert.equal(r.retenidas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.ok(m.archivos.has(FID_VIEJA));
  const c = m.leer(cola('ana', FID_VIEJA));
  assert.equal(c.estado, 'retenida');
  assert.equal(c.motivo, 'historial');
  assert.equal(Date.parse(c.nextAttemptAt), NOW_MS + RETENIDA_REVISION_MS);
  assert.equal(m.leer('interestRequests/c1_lote1').loteFoto, m.url(FID_VIEJA)); // el historial no cambió
});

test('2. una foto referenciada por una cotización NO se elimina', async () => {
  const m = await escenario();
  m.poner('quotes/q1', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.cola('ana', FID_VIEJA);
  const r = await llamar(m, 'ana');
  assert.equal(r.retenidas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'retenida');
});

test('3. una URL guardada con parámetros añadidos también cuenta como referencia (prefijo)', async () => {
  const m = await escenario();
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: `${m.url(FID_VIEJA)}?tr=w-300` });
  m.cola('ana', FID_VIEJA);
  assert.equal((await llamar(m, 'ana')).retenidas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
});

test('un loteFoto null o de otra foto no retiene nada', async () => {
  const m = await escenario();
  m.poner('interestRequests/a', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: null });
  m.poner('quotes/b', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_ACTUAL) });
  m.cola('ana', FID_VIEJA);
  assert.equal((await llamar(m, 'ana')).completadas, 1);
  assert.equal(m.archivos.has(FID_VIEJA), false);
  assert.ok(m.archivos.has(FID_ACTUAL));
});

// ---------- 4. Sustituir una foto no rompe el historial ----------

test('4. sustituir la foto de un lote que sigue existiendo: la vieja se conserva mientras el historial la use', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [m.url(FID_NUEVA)], fotosStoragePaths: [FID_NUEVA] }); // ya guarda la nueva
  m.poner('interestRequests/c1_lote1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.cola('ana', FID_VIEJA, { refId: 'lote1' });
  await llamar(m, 'ana');
  assert.ok(m.archivos.has(FID_VIEJA), 'la imagen del historial sigue existiendo');
  assert.ok(m.archivos.has(FID_NUEVA));
  assert.equal(m.leer('interestRequests/c1_lote1').loteFoto, m.url(FID_VIEJA));
  assert.equal(m.leer('quotes/q1').loteFoto, m.url(FID_VIEJA));
  assert.equal(escriturasA(m, 'interestRequests').length + escriturasA(m, 'quotes').length, 0, 'el Worker no tocó el historial');
  // Reintentar no cambia nada (idempotente) ni gasta intentos.
  const otra = await llamar(m, 'ana', NOW_MS + 1000);
  assert.equal(otra.procesadas, 0);
});

test('una foto retenida se revisa sola pasado el plazo: si el historial ya no la usa, se borra', async () => {
  const m = await escenario();
  m.poner('interestRequests/c1_lote1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.cola('ana', FID_VIEJA);
  await llamar(m, 'ana');
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'retenida');
  // Antes del plazo el cron no la toca.
  assert.equal((await cron(m, NOW_MS + DIA)).procesadas, 0);
  // Pasado el plazo y sin copias históricas, se resuelve sola.
  m.poner('interestRequests/c1_lote1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: null });
  const r = await cron(m, NOW_MS + RETENIDA_REVISION_MS + 1000);
  assert.equal(r.completadas, 1);
  assert.equal(m.archivos.has(FID_VIEJA), false);
});

test('si el historial sigue usando la foto, la revisión periódica la mantiene retenida (no queda atascada)', async () => {
  const m = await escenario();
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.cola('ana', FID_VIEJA);
  await llamar(m, 'ana');
  const ahora = NOW_MS + RETENIDA_REVISION_MS + 1000;
  const r = await cron(m, ahora);
  assert.equal(r.retenidas, 1);
  assert.equal(Date.parse(m.leer(cola('ana', FID_VIEJA)).nextAttemptAt), ahora + RETENIDA_REVISION_MS);
  assert.ok(m.archivos.has(FID_VIEJA));
});

// ---------- 5. No se borra lo que se usa ----------

test('5. un lote vigente, un perfil y el historial: ninguna de las tres usos permite borrar', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [m.url(FID_ACTUAL)], fotosStoragePaths: [FID_ACTUAL] });
  m.poner('sellerProfiles/ana', { fotoPrincipal: m.url(FID_NUEVA), fotoPrincipalStoragePath: FID_NUEVA });
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  for (const f of [FID_ACTUAL, FID_NUEVA, FID_VIEJA]) m.cola('ana', f);
  const r = await llamar(m, 'ana');
  assert.equal(r.enUso, 2);
  assert.equal(r.retenidas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.archivos.size, 3);
});

test('«enUso» no es un callejón sin salida: la app puede reabrirla y entonces se procesa de cero', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [m.url(FID_ACTUAL)], fotosStoragePaths: [FID_ACTUAL] });
  m.cola('ana', FID_ACTUAL);
  await llamar(m, 'ana');
  assert.equal(m.leer(cola('ana', FID_ACTUAL)).estado, 'enUso');
  assert.equal(m.leer(cola('ana', FID_ACTUAL)).intentos, 0);
  // El vendedor quita de verdad la foto y la app reabre la solicitud (regla: enUso → pendiente).
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [], fotosStoragePaths: [] });
  m.docs.get(cola('ana', FID_ACTUAL)).fields.estado = { stringValue: 'pendiente' };
  assert.equal((await llamar(m, 'ana', NOW_MS + 1000)).completadas, 1);
  assert.equal(m.archivos.has(FID_ACTUAL), false);
});

test('una solicitud «fallido» que la app reabre empieza de cero (no vuelve a fallar al primer error)', async () => {
  const m = await escenario();
  m.cola('ana', FID_VIEJA, { estado: 'pendiente', intentos: 6 }); // reabierta tras agotar los intentos
  m.fallos.imagekitBorrar = [503];
  const r = await llamar(m, 'ana');
  assert.equal(r.reintentos, 1);
  const c = m.leer(cola('ana', FID_VIEJA));
  assert.equal(c.estado, 'errorTemporal'); // no «fallido»
  assert.equal(c.intentos, 1);
});

// ---------- 6. Aislamiento entre personas ----------

test('6. no se puede pedir la eliminación del lote de OTRA persona: se rechaza y nada cambia', async () => {
  const m = await escenario();
  m.poner('coffeeLots/loteBeto', { sellerId: 'beto', fotos: [], fotosStoragePaths: [] });
  m.poner('interestRequests/c1_loteBeto', { sellerId: 'beto', coffeeLotId: 'loteBeto', loteFoto: 'https://ik.imagekit.io/demo/beto.jpg' });
  m.poner('quotes/q1', { sellerId: 'beto', coffeeLotId: 'loteBeto', loteFoto: 'https://ik.imagekit.io/demo/beto.jpg' });
  m.poner(colaLote('ana', 'loteBeto'), { lotId: 'loteBeto', estado: 'pendiente' }); // ana lo pide
  const r = await llamar(m, 'ana');
  assert.equal(r.rechazadas, 1);
  assert.equal(m.leer(colaLote('ana', 'loteBeto')).motivo, 'no_es_del_usuario');
  assert.ok(m.docs.has('coffeeLots/loteBeto'));
  assert.equal(m.leer('interestRequests/c1_loteBeto').loteFoto, 'https://ik.imagekit.io/demo/beto.jpg');
  assert.equal(m.leer('quotes/q1').loteFoto, 'https://ik.imagekit.io/demo/beto.jpg');
  assert.equal(escriturasA(m, 'interestRequests').length + escriturasA(m, 'quotes').length, 0);
});

test('6b. aunque el lote ya no exista, solo se limpian las negociaciones DEL VENDEDOR que lo pide', async () => {
  const m = await escenario();
  m.poner('interestRequests/c1_x', { sellerId: 'ana', coffeeLotId: 'loteGone', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
  m.poner('interestRequests/c2_x', { sellerId: 'beto', coffeeLotId: 'loteGone', loteFoto: 'https://ik.imagekit.io/demo/b.jpg' });
  m.poner('quotes/q1', { sellerId: 'beto', coffeeLotId: 'loteGone', loteFoto: 'https://ik.imagekit.io/demo/b.jpg' });
  m.poner(colaLote('ana', 'loteGone'), { lotId: 'loteGone', estado: 'pendiente' });
  await llamar(m, 'ana');
  assert.equal(m.leer('interestRequests/c1_x').loteFoto, null);
  assert.equal(m.leer('interestRequests/c2_x').loteFoto, 'https://ik.imagekit.io/demo/b.jpg');
  assert.equal(m.leer('quotes/q1').loteFoto, 'https://ik.imagekit.io/demo/b.jpg');
});

test('6c. el cuerpo de la petición no puede indicar qué lote o foto tocar', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [], fotosStoragePaths: [] });
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
  const t = await tokenDe(m, 'ana');
  const req = new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${t}` }, body: JSON.stringify({ lotId: 'lote1', fileId: FID_VIEJA }) });
  const r = await (await handle(req, ENVR, { fetch: m.fetch, nowMs: NOW_MS })).json();
  assert.equal(r.procesadas, 0);
  assert.equal(m.leer('quotes/q1').loteFoto, 'https://ik.imagekit.io/demo/a.jpg');
});

// ---------- 7. Eliminación completa del lote ----------

/** Lote ya vaciado por la app (estado borrador, sin fotos) con historial y fotos en la cola. */
async function loteEliminado() {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', estado: 'borrador', fotos: [], fotosStoragePaths: [] });
  m.poner('coffeeLots/lote2', { sellerId: 'ana', estado: 'publicado', fotos: [m.url(FID_NUEVA)], fotosStoragePaths: [FID_NUEVA] });
  m.poner('interestRequests/c1_lote1', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.poner('interestRequests/c1_lote2', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote2', loteFoto: m.url(FID_NUEVA) });
  m.poner('quotes/q1', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: m.url(FID_VIEJA) });
  m.poner('quotes/q2', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'lote2', loteFoto: m.url(FID_NUEVA) });
  m.cola('ana', FID_ACTUAL, { refId: 'lote1' }); // foto vigente al eliminar, encolada por la app
  m.cola('ana', FID_VIEJA, { refId: 'lote1', estado: 'retenida' }); // foto reemplazada antes, retenida por el historial
  m.docs.get(cola('ana', FID_VIEJA)).fields.nextAttemptAt = { timestampValue: new Date(NOW_MS + RETENIDA_REVISION_MS).toISOString() };
  m.poner(colaLote('ana', 'lote1'), { lotId: 'lote1', estado: 'pendiente' });
  return m;
}

test('7. eliminar un lote: sus referencias históricas quedan en null (solo loteFoto) y las demás no se tocan', async () => {
  const m = await loteEliminado();
  const r = await llamar(m, 'ana');
  assert.equal(r.lotes, 1);
  assert.equal(m.leer('interestRequests/c1_lote1').loteFoto, null);
  assert.equal(m.leer('quotes/q1').loteFoto, null);
  assert.equal(m.leer('interestRequests/c1_lote2').loteFoto, m.url(FID_NUEVA)); // otro lote: intacto
  assert.equal(m.leer('quotes/q2').loteFoto, m.url(FID_NUEVA));
  assert.equal(m.docs.has('coffeeLots/lote1'), false);
  assert.ok(m.docs.has('coffeeLots/lote2'));
  assert.equal(m.leer(colaLote('ana', 'lote1')).estado, 'completado');
  // El Worker solo escribió `loteFoto` en el historial y nada más.
  for (const e of [...escriturasA(m, 'interestRequests'), ...escriturasA(m, 'quotes')]) assert.deepEqual(e.campos, ['loteFoto'], e.ruta);
  // Los demás campos del historial siguen ahí.
  assert.equal(m.leer('interestRequests/c1_lote1').compradorId, 'c1');
  assert.equal(m.leer('quotes/q1').sellerId, 'ana');
});

test('7b. tras eliminar el lote, las fotos retenidas se liberan y se borran; ninguna imagen en uso se pierde', async () => {
  const m = await loteEliminado();
  await llamar(m, 'ana'); // 1.ª pasada: limpia el historial, borra el lote y borra la foto vigente
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'pendiente'); // liberada
  assert.equal(m.archivos.has(FID_ACTUAL), false);
  await llamar(m, 'ana', NOW_MS + 1000); // 2.ª pasada: ya nadie usa la vieja
  assert.equal(m.archivos.has(FID_VIEJA), false);
  assert.ok(m.archivos.has(FID_NUEVA), 'la foto del otro lote sigue intacta');
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'completado');
});

test('7c. si la app no encoló las fotos del lote, el Worker lo hace antes de borrarlo (red de seguridad)', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [m.url(FID_ACTUAL)], fotosStoragePaths: [FID_ACTUAL, ''] });
  m.poner(colaLote('ana', 'lote1'), { lotId: 'lote1', estado: 'pendiente' });
  await llamar(m, 'ana');
  assert.equal(m.docs.has('coffeeLots/lote1'), false);
  const c = m.leer(cola('ana', FID_ACTUAL));
  assert.equal(c.origen, 'lot');
  assert.equal(c.refId, 'lote1');
  await llamar(m, 'ana', NOW_MS + 1000);
  assert.equal(m.archivos.has(FID_ACTUAL), false);
});

test('7d. con muchas negociaciones se procesa por tandas sin gastar intentos', async () => {
  const m = await escenario();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', fotos: [], fotosStoragePaths: [] });
  for (let i = 0; i < LIMITE_HISTORICOS + 5; i++) m.poner(`interestRequests/c${i}_lote1`, { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: `https://ik.imagekit.io/demo/${i}.jpg` });
  m.poner(colaLote('ana', 'lote1'), { lotId: 'lote1', estado: 'pendiente' });
  await llamar(m, 'ana');
  assert.equal(m.leer(colaLote('ana', 'lote1')).estado, 'pendiente');
  assert.equal(m.leer(colaLote('ana', 'lote1')).intentos, 0);
  assert.ok(m.docs.has('coffeeLots/lote1'), 'el lote no se borra hasta limpiar todo el historial');
  await llamar(m, 'ana', NOW_MS + 1000);
  assert.equal(m.leer(colaLote('ana', 'lote1')).estado, 'completado');
  for (let i = 0; i < LIMITE_HISTORICOS + 5; i++) assert.equal(m.leer(`interestRequests/c${i}_lote1`).loteFoto, null);
});

// ---------- 8. Interrupciones y recuperación ----------

test('8a. interrupción a mitad (falla el commit de cotizaciones): se recupera sin perder integridad', async () => {
  const m = await loteEliminado();
  m.fallos.firestoreCommit = [null, 500]; // 1.º (solicitudes) ok, 2.º (cotizaciones) falla
  const r1 = await llamar(m, 'ana');
  assert.equal(r1.reintentos, 1);
  assert.equal(m.leer('interestRequests/c1_lote1').loteFoto, null); // ya limpiado
  assert.equal(m.leer('quotes/q1').loteFoto, m.url(FID_VIEJA)); // aún no
  assert.ok(m.docs.has('coffeeLots/lote1'), 'el lote NO se borra hasta terminar la limpieza');
  assert.equal(m.leer(colaLote('ana', 'lote1')).estado, 'errorTemporal');
  assert.ok(m.archivos.has(FID_VIEJA), 'nada de ImageKit se borró con el historial a medias');
  // Reintento tras la espera: completa lo que faltaba.
  const r2 = await llamar(m, 'ana', NOW_MS + esperaTrasIntento(1) + 1000);
  assert.equal(r2.lotes, 1);
  assert.equal(m.leer('quotes/q1').loteFoto, null);
  assert.equal(m.docs.has('coffeeLots/lote1'), false);
});

test('8b. interrupción DESPUÉS de borrar el lote (falla al liberar las retenidas): al repetir se completa', async () => {
  const m = await loteEliminado();
  m.antesDeCommit = (writes) => (writes.some((w) => w.updateMask?.fieldPaths?.includes('ultimoError')) ? 500 : null);
  const r1 = await llamar(m, 'ana');
  assert.equal(r1.reintentos, 1);
  assert.equal(m.docs.has('coffeeLots/lote1'), false); // el lote ya se había borrado
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'retenida'); // aún sin liberar
  m.antesDeCommit = null;
  const r2 = await llamar(m, 'ana', NOW_MS + esperaTrasIntento(1) + 1000); // el lote ya no existe: no pasa nada
  assert.equal(r2.lotes, 1);
  assert.equal(m.leer(cola('ana', FID_VIEJA)).estado, 'pendiente');
  await llamar(m, 'ana', NOW_MS + esperaTrasIntento(1) + 2000);
  assert.equal(m.archivos.has(FID_VIEJA), false);
});

test('8c. un proceso que murió (lease vencido) se retoma desde el cron sin duplicar nada', async () => {
  const m = await loteEliminado();
  m.docs.get(colaLote('ana', 'lote1')).fields.estado = { stringValue: 'procesando' };
  m.docs.get(colaLote('ana', 'lote1')).fields.leaseUntil = { timestampValue: new Date(NOW_MS + 60_000).toISOString() };
  assert.equal((await cron(m)).lotes, 0); // lease vigente: otra ejecución lo está haciendo
  const r = await cron(m, NOW_MS + 10 * 60_000);
  assert.equal(r.lotes, 1);
  assert.equal(m.leer(colaLote('ana', 'lote1')).estado, 'completado');
});

test('8d. si falla el borrado de ImageKit tras limpiar el historial, la foto sigue en la cola y se reintenta', async () => {
  const m = await loteEliminado();
  m.fallos.imagekitBorrar = [503];
  await llamar(m, 'ana');
  assert.equal(m.leer(cola('ana', FID_ACTUAL)).estado, 'errorTemporal');
  await llamar(m, 'ana', NOW_MS + esperaTrasIntento(1) + 1000);
  assert.equal(m.archivos.has(FID_ACTUAL), false);
});

// ---------- 9. Idempotencia ----------

test('9. repetir la eliminación del lote (solicitud duplicada) no cambia nada ni falla', async () => {
  const m = await loteEliminado();
  await llamar(m, 'ana');
  const antes = JSON.stringify([...m.docs.entries()].filter(([k]) => !k.startsWith('users/')));
  const llamadasAntes = m.llamadas.length;
  // Simula una solicitud duplicada: la cola vuelve a «pendiente» tras completarse.
  m.docs.get(colaLote('ana', 'lote1')).fields.estado = { stringValue: 'pendiente' };
  const r = await llamar(m, 'ana', NOW_MS + 5000);
  assert.equal(r.lotes, 1);
  assert.equal(JSON.stringify([...m.docs.entries()].filter(([k]) => !k.startsWith('users/'))), antes);
  assert.ok(m.llamadas.length > llamadasAntes);
  assert.equal(m.cuenta('commit'), m.llamadas.filter((l) => l.tipo === 'commit').length);
});

test('9b. el borrado remoto repetido sigue siendo idempotente (404 ya borrado) y la historia no se rompe', async () => {
  const m = await escenario();
  m.cola('ana', FID_VIEJA);
  await llamar(m, 'ana');
  assert.equal(m.cuenta('imagekitBorrar'), 1);
  m.docs.get(cola('ana', FID_VIEJA)).fields.estado = { stringValue: 'pendiente' };
  const r = await llamar(m, 'ana', NOW_MS + 5000);
  assert.equal(r.completadas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 1); // no se vuelve a borrar: ImageKit ya no tiene el archivo
});

// ---------- Presupuesto de subpeticiones (plan gratuito: 50) ----------

test('el peor caso de una llamada (1 lote + fotos al máximo, con todas las comprobaciones) cabe en 50 subpeticiones', async () => {
  const m = await loteEliminado();
  for (let i = 0; i < MAX_POR_EJECUCION + 2; i++) {
    const id = `5f8a1c2b3d4e5f6a7b8c9e${String(i).padStart(2, '0')}`;
    m.archivo(id, rutaImg('ana', `x${i}.jpg`));
    m.cola('ana', id);
  }
  await llamar(m, 'ana');
  const jwksYOauth = 2; // claves de Firebase + token de la cuenta de servicio
  assert.ok(m.llamadas.length + jwksYOauth <= 50, `subpeticiones: ${m.llamadas.length + jwksYOauth}`);
});
