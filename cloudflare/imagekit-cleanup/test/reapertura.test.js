// Reapertura de solicitudes «fallido» y coherencia de estados entre la app, las reglas y el Worker.
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { handle, resetLimitador } from '../src/index.js';
import { resetJwksCache } from '../src/firebase.js';
import { resetAuthCache } from '../src/google-auth.js';
import { MAX_INTENTOS, esProcesable } from '../src/cleanup.js';
import { ENV, NOW_MS, RAIZ, mundoConClaves, tokenDe } from './backend-falso.js';

const FID = '5f8a1c2b3d4e5f6a7b8c9d21';
const rutaImg = (uid) => `${RAIZ}/users/${uid}/lots/f.jpg`;
const cola = (uid, id) => `users/${uid}/pendingFileDeletions/${id}`;
const colaLote = (uid, id) => `users/${uid}/pendingLotDeletions/${id}`;
const texto = (s) => ({ stringValue: s });
const entero = (n) => ({ integerValue: String(n) });
const tiempo = (ms) => ({ timestampValue: new Date(ms).toISOString() });

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

/**
 * Deja una solicitud en el estado en que la dejaría un ciclo agotado y REABIERTO por la app:
 * la app solo cambia `estado` y `createdAt` (lo único que permiten las reglas), así que
 * `intentos`, `ultimoError`, `motivo` y demás campos del Worker quedan como estaban.
 */
function reabierta(m, ruta, base) {
  m.poner(ruta, base);
  const f = m.docs.get(ruta).fields;
  f.estado = texto('pendiente');
  f.intentos = entero(MAX_INTENTOS);
  f.ultimoError = texto('imagekit_5xx');
  f.motivo = texto('ciclo_anterior');
  f.nextAttemptAt = tiempo(NOW_MS + 3600_000);
}

// ---- 1, 3, 4. Foto: reapertura, contador y último error ----

test('foto «fallido» reabierta: se procesa de cero, el contador se reinicia y el error se limpia', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  const r = await llamar(m, 'ana');
  assert.equal(r.completadas, 1);
  assert.equal(m.archivos.has(FID), false);
  const c = m.leer(cola('ana', FID));
  assert.equal(c.estado, 'completado');
  assert.equal(c.intentos, 1, 'empezó de cero (no 7)');
  assert.equal(c.ultimoError, undefined);
  assert.equal(c.nextAttemptAt, undefined);
  assert.equal(c.leaseUntil, undefined);
  assert.equal(c.motivo, 'borrado'); // el del ciclo nuevo, no «ciclo_anterior»
});

test('foto reabierta que vuelve a fallar: NO pasa directo a «fallido»; el error se REEMPLAZA por el nuevo', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  m.fallos.imagekitDetalles = [429]; // error distinto del anterior (imagekit_5xx)
  const r = await llamar(m, 'ana');
  assert.equal(r.reintentos, 1);
  const c = m.leer(cola('ana', FID));
  assert.equal(c.estado, 'errorTemporal');
  assert.equal(c.intentos, 1);
  assert.equal(c.ultimoError, 'imagekit_429');
  assert.ok(Date.parse(c.nextAttemptAt) > NOW_MS, 'espera nueva, no la del ciclo anterior');
  assert.ok(Date.parse(c.nextAttemptAt) < NOW_MS + 3600_000, 'la espera vieja se descartó');
});

test('el error y la espera del ciclo anterior se limpian AL RECLAMAR la reabierta (aunque el proceso muera después)', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  m.fallos.firestoreActualizar = [null, 500, 500]; // reclamar ok; fallan el cierre y el intento de anotar el error
  await llamar(m, 'ana');
  const c = m.leer(cola('ana', FID));
  assert.equal(c.estado, 'procesando'); // quedó a medias
  assert.equal(c.intentos, 1);
  assert.equal(c.ultimoError, undefined);
  assert.equal(c.nextAttemptAt, undefined);
  assert.equal(c.motivo, undefined);
  // Pasado el lease se retoma: el archivo ya no existe en ImageKit → completado, sin borrar dos veces.
  const r = await llamar(m, 'ana', NOW_MS + 10 * 60_000);
  assert.equal(r.completadas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 1);
  assert.equal(m.leer(cola('ana', FID)).estado, 'completado');
});

// ---- 2, 3, 4. Lote: reapertura, contador y último error ----

test('solicitud de lote «fallido» reabierta: se procesa de cero, contador a 0 y error limpio', async () => {
  const m = await mundoConClaves();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', estado: 'borrador', fotos: [], fotosStoragePaths: [] });
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
  reabierta(m, colaLote('ana', 'lote1'), { lotId: 'lote1', estado: 'pendiente' });
  const r = await llamar(m, 'ana');
  assert.equal(r.lotes, 1);
  const c = m.leer(colaLote('ana', 'lote1'));
  assert.equal(c.estado, 'completado');
  assert.equal(c.intentos, 0);
  assert.equal(c.ultimoError, undefined);
  assert.equal(c.nextAttemptAt, undefined);
  assert.equal(c.motivo, undefined);
  assert.equal(m.leer('quotes/q1').loteFoto, null);
  assert.equal(m.docs.has('coffeeLots/lote1'), false);
});

test('lote reabierto que vuelve a fallar: errorTemporal con intento 1 y el error nuevo', async () => {
  const m = await mundoConClaves();
  m.poner('coffeeLots/lote1', { sellerId: 'ana', estado: 'borrador', fotos: [], fotosStoragePaths: [] });
  reabierta(m, colaLote('ana', 'lote1'), { lotId: 'lote1', estado: 'pendiente' });
  m.fallos.firestoreCommit = [500];
  m.poner('quotes/q1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
  await llamar(m, 'ana');
  const c = m.leer(colaLote('ana', 'lote1'));
  assert.equal(c.estado, 'errorTemporal');
  assert.equal(c.intentos, 1);
  assert.match(c.ultimoError, /^firestore_/);
  assert.notEqual(c.ultimoError, 'imagekit_5xx');
});

// ---- 5. Una solicitud completada no se reprocesa por accidente ----

test('«completado» (y los demás estados cerrados) no se procesan aunque conserven intentos altos', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  for (const estado of ['completado', 'rechazado', 'fallido', 'enUso']) {
    m.poner(cola('ana', `${FID.slice(0, -2)}${estado.length}0`), { fileId: FID, origen: 'lot', estado, intentos: MAX_INTENTOS });
  }
  m.poner(colaLote('ana', 'loteHecho'), { lotId: 'loteHecho', estado: 'completado', intentos: MAX_INTENTOS });
  const r = await llamar(m, 'ana');
  assert.equal(r.procesadas, 0);
  assert.equal(m.llamadas.filter((l) => l.tipo !== 'listar').length, 0, 'ni una llamada a ImageKit ni escrituras');
  assert.equal(m.escrituras.length, 0);
  assert.ok(m.archivos.has(FID));
});

test('una foto «retenida» antes de su fecha, o un lote «completado», no se tocan; «retenida» vencida sí se revisa', () => {
  const doc = (estado, extra = {}) => ({ fields: { estado: texto(estado), ...extra } });
  assert.equal(esProcesable(doc('completado'), NOW_MS), false);
  assert.equal(esProcesable(doc('fallido'), NOW_MS), false);
  assert.equal(esProcesable(doc('retenida', { nextAttemptAt: tiempo(NOW_MS + 1000) }), NOW_MS), false);
  assert.equal(esProcesable(doc('retenida', { nextAttemptAt: tiempo(NOW_MS - 1000) }), NOW_MS), true);
  assert.equal(esProcesable(doc('pendiente'), NOW_MS), true);
});

// ---- 7. Idempotencia / sin duplicados al reintentar ----

test('reintentar la reapertura no duplica el trabajo: un solo borrado y una sola solicitud', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  await llamar(m, 'ana');
  await llamar(m, 'ana', NOW_MS + 1000);
  await llamar(m, 'ana', NOW_MS + 2000);
  assert.equal(m.cuenta('imagekitBorrar'), 1);
  assert.equal([...m.docs.keys()].filter((k) => k.startsWith('users/ana/pendingFileDeletions/')).length, 1);
  assert.equal(m.leer(cola('ana', FID)).estado, 'completado');
});

// ---- 6. Otro propietario ----

test('el Worker solo reabre/procesa la cola del usuario del token: la solicitud reabierta de ana no la procesa beto', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  const r = await llamar(m, 'beto');
  assert.equal(r.procesadas, 0);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.leer(cola('ana', FID)).estado, 'pendiente');
  assert.equal(m.leer(cola('ana', FID)).intentos, MAX_INTENTOS, 'sin tocar');
});

test('reabrir no toca el historial: una foto reabierta que el historial usa queda «retenida» y loteFoto no cambia', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  const url = m.archivos.get(FID).url;
  m.poner('interestRequests/c1_lote1', { sellerId: 'ana', coffeeLotId: 'lote1', loteFoto: url });
  reabierta(m, cola('ana', FID), { fileId: FID, origen: 'lot', estado: 'pendiente' });
  const r = await llamar(m, 'ana');
  assert.equal(r.retenidas, 1);
  assert.ok(m.archivos.has(FID));
  assert.equal(m.leer('interestRequests/c1_lote1').loteFoto, url);
  assert.equal(m.escrituras.filter((e) => e.ruta.startsWith('interestRequests')).length, 0);
});

// ---- Coherencia de nombres y transiciones entre app, reglas y Worker ----

const ESTADOS = ['pendiente', 'procesando', 'completado', 'enUso', 'retenida', 'rechazado', 'errorTemporal', 'fallido'];
const leer = (ruta) => readFileSync(new URL(ruta, import.meta.url), 'utf8');
const literales = (texto, re) => [...texto.matchAll(re)].map((m) => m[1]);

test('contrato de estados: la app, las reglas y el Worker usan los mismos nombres', () => {
  const reglas = leer('../../../firestore.rules');
  const bloque = (nombre) => reglas.slice(reglas.indexOf(`match /${nombre}/`), reglas.indexOf('allow delete: if false;', reglas.indexOf(`match /${nombre}/`)));
  const dart = ['pending_deletions.dart', 'coffee_lot_repository.dart'].map((f) => leer(`../../../lib/repositories/${f}`)).join('\n');
  const worker = readdirSync(new URL('../src/', import.meta.url)).filter((f) => f.endsWith('.js')).map((f) => leer(`../src/${f}`)).join('\n');

  // Todo literal de estado de las COLAS en reglas, app y Worker pertenece al vocabulario común
  // (los estados de lotes y negociaciones, como «publicado», son otro vocabulario y no se mezclan).
  const reglasCola = `${bloque('pendingFileDeletions')}\n${bloque('pendingLotDeletions')}`;
  for (const origen of [
    literales(reglasCola, /estado\s*(?:==|!=)\s*'(\w+)'/g),
    literales(reglasCola, /estado\s+in\s+\[([^\]]*)\]/g).flatMap((l) => l.split(',').map((x) => x.replace(/[\s']/g, ''))),
    literales(dart, /'estado':\s*'(\w+)'/g),
    literales(dart, /estado\s*==\s*'(\w+)'/g),
    literales(dart, /isEqualTo:\s*'(\w+)'/g),
    literales(worker, /vTexto\('(\w+)'\)/g).filter((x) => ESTADOS.includes(x)),
    literales(worker, /cerrar\('(\w+)'/g),
  ]) for (const e of origen) assert.ok(ESTADOS.includes(e), `estado desconocido «${e}»`);

  // Transiciones de reapertura: lo que la app reabre == lo que las reglas permiten == lo que el Worker reinicia.
  assert.match(bloque('pendingFileDeletions'), /estado in \['enUso', 'fallido'\]/);
  assert.match(bloque('pendingLotDeletions'), /resource\.data\.estado == 'fallido'/);
  assert.match(dart, /estado == 'enUso' \|\| estado == 'fallido'/); // encolar (foto)
  assert.match(dart, /where\('estado', isEqualTo: 'fallido'\)/); // reabrirFotosFallidas
  assert.match(dart, /existente\.data\(\)\?\['estado'\] == 'fallido'/); // encolarBorradoDeLote
  assert.match(worker, /reabierta = texto\(doc, 'estado'\) === 'pendiente' && entero\(doc, 'intentos'\) >= MAX_INTENTOS/);
  // «retenida» y «completado» nunca los reabre la app.
  for (const prohibido of ["'retenida'", "'completado'"]) assert.ok(!bloque('pendingFileDeletions').match(new RegExp(`resource\\.data\\.estado[^;]*${prohibido}`)));
  // Las reglas permiten que la reapertura solo cambie estado y createdAt.
  assert.match(bloque('pendingFileDeletions'), /touchesOnly\(\['estado', 'createdAt'\]\)/);
  assert.match(bloque('pendingLotDeletions'), /touchesOnly\(\['estado', 'createdAt'\]\)/);
});
