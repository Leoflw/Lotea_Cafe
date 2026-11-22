// Etapa 6: solicitar y cancelar la eliminación de cuenta. Reloj inyectado, Firestore simulado
// (con transacciones, precondiciones y detección de conflictos). Nada toca la red.
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handle, resetLimitador } from '../src/index.js';
import { resetJwksCache, verifyIdToken, ReauthError } from '../src/firebase.js';
import { resetAuthCache } from '../src/google-auth.js';
import { BORRADO_DEFINITIVO_IMPLEMENTADO, MAX_CAFES, dryRunActivo, retencionDias } from '../src/account-deletion.js';
import { ENV, NOW_MS, PROYECTO, firmarToken, mundoConClaves, nuevaClave } from './backend-falso.js';

const DIA = 24 * 60 * 60 * 1000;
const iso = (ms) => new Date(ms).toISOString();

async function envConCuenta(extra = {}) {
  const par = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', par.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return { ...ENV, RETENCION_DIAS: '15', DRY_RUN: 'true', ...extra, CLEANUP_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'limpieza@lotea-cafe.iam.gserviceaccount.com', private_key: pem, project_id: PROYECTO }) };
}
const ENVA = await envConCuenta();

beforeEach(() => {
  resetLimitador();
  resetJwksCache();
  resetAuthCache();
});

const generadorDeIds = () => {
  let n = 0;
  return () => `sol-${++n}`;
};

/** POST a una ruta del Worker con un ID token fresco (auth_time = hace 10 s salvo que se indique). */
async function pedir(m, ruta, uid, { nowMs = NOW_MS, env = ENVA, extra = {}, body = {}, metodo = 'POST', token, idFn, url, fetchFn } = {}) {
  const t = token ?? (await firmarToken(m.claves, 'kid1', uid, extra, nowMs));
  const init = { method: metodo, headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json' } };
  if (metodo === 'POST') init.body = JSON.stringify(body);
  const r = await handle(new Request(url ?? `https://x.workers.dev${ruta}`, init), env, { fetch: fetchFn ?? m.fetch, nowMs, idFn: idFn ?? m.idFn });
  return { status: r.status, json: await r.json() };
}
const solicitar = (m, uid, o) => pedir(m, '/account-deletion/request', uid, o);
const cancelar = (m, uid, o) => pedir(m, '/account-deletion/cancel', uid, o);

const lote = (m, id, campos = {}) =>
  m.poner(`coffeeLots/${id}`, { sellerId: 'ana', nombre: `Café ${id}`, estado: 'publicado', fotos: [`https://ik.imagekit.io/demo/lotea-cafe/users/ana/lots/${id}.jpg`], fotosStoragePaths: [`5f8a1c2b3d4e5f6a7b8c9d${id.padStart(2, '0')}`], precioCOP: 32000, ...campos });

async function mundo({ cuenta, conLotes = true } = {}) {
  resetJwksCache(); // cada mundo tiene su propio par de claves
  resetAuthCache();
  resetLimitador();
  const m = await mundoConClaves();
  m.idFn = generadorDeIds();
  m.poner('users/ana', { uid: 'ana', email: 'ana@x.co', rol: 'vendedor', nombre: 'Ana', ...(cuenta ? { cuentaEstado: cuenta } : {}) });
  m.poner('users/bob', { uid: 'bob', email: 'bob@x.co', rol: 'vendedor', nombre: 'Bob' });
  if (conLotes) {
    lote(m, '01'); // publicado de ana
    lote(m, '02', { estado: 'borrador' }); // borrador de ana
    lote(m, '03', { estado: 'suspendido', estadoPrevio: 'publicado', suspensionSolicitudId: 'otra-causa' }); // suspendido por otra razón
    lote(m, '04', { sellerId: 'bob' }); // publicado de otra persona
    m.poner('sellerProfiles/ana', { usuarioId: 'ana', nombreMarca: 'Finca Ana' });
    m.poner('interestRequests/c1_01', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: '01', estado: 'aceptada', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
    m.poner('quotes/q1', { compradorId: 'c1', sellerId: 'ana', coffeeLotId: '01', estado: 'ofertaEnviada', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
    m.poner('chats/c1_01/messages/m1', { senderId: 'c1', texto: 'hola' });
  }
  return m;
}
const instantanea = (m, ruta) => JSON.stringify(m.docs.get(ruta));
const todas = (m) => JSON.stringify([...m.docs.entries()]);

// ---------------------------------------------------------------------------------------------
// Autenticación y antigüedad de la sesión
// ---------------------------------------------------------------------------------------------

test('ID token inválido: 401 y no se toca nada', async () => {
  const m = await mundo();
  const antes = todas(m);
  const r = await solicitar(m, 'ana', { token: 'no.es.un-token' });
  assert.equal(r.status, 401);
  assert.equal(r.json.codigo, 'sesion');
  assert.equal(todas(m), antes);
  const sinCabecera = await handle(new Request('https://x.workers.dev/account-deletion/request', { method: 'POST' }), ENVA, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(sinCabecera.status, 401);
});

test('token firmado por otra clave: 401', async () => {
  const m = await mundo();
  const otra = await nuevaClave('kid1');
  const token = await firmarToken(otra, 'kid1', 'ana');
  assert.equal((await solicitar(m, 'ana', { token })).status, 401);
  assert.equal(m.leer('users/ana').cuentaEstado, undefined);
});

test('auth_time de 301 segundos o más se rechaza en las rutas de cuenta, con mensaje genérico de reautenticación', async () => {
  const m = await mundo();
  const antes = todas(m);
  const ahora = Math.floor(NOW_MS / 1000);
  for (const ruta of ['/account-deletion/request', '/account-deletion/cancel']) {
    for (const edad of [301, 302, 3600]) {
      resetLimitador();
      const r = await pedir(m, ruta, 'ana', { extra: { auth_time: ahora - edad } });
      assert.equal(r.status, 401, `${ruta} edad ${edad}`);
      assert.equal(r.json.codigo, 'reautenticacion');
      assert.ok(!JSON.stringify(r.json).includes('ana'));
    }
  }
  assert.equal(todas(m), antes);
});

test('auth_time reciente (hasta 300 s) se acepta', async () => {
  const m = await mundo();
  const ahora = Math.floor(NOW_MS / 1000);
  const r = await solicitar(m, 'ana', { extra: { auth_time: ahora - 300 } });
  assert.equal(r.status, 200);
  assert.equal(r.json.estado, 'eliminacionPendiente');
});

test('la ruta de limpieza POST / NO hereda el límite de cinco minutos', async () => {
  const m = await mundo();
  const ahora = Math.floor(NOW_MS / 1000);
  const token = await firmarToken(m.claves, 'kid1', 'ana', { auth_time: ahora - 86_400 });
  const r = await handle(new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }), ENVA, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(r.status, 200);
  // y verifyIdToken, sin la opción, no impone ningún límite
  const payload = await verifyIdToken(token, { projectId: PROYECTO, fetchFn: m.fetch, nowMs: NOW_MS });
  assert.equal(payload.sub, 'ana');
  await assert.rejects(verifyIdToken(token, { projectId: PROYECTO, fetchFn: m.fetch, nowMs: NOW_MS, maxAuthAgeSeconds: 300 }), ReauthError);
});

test('un UID enviado en el cuerpo, la query o una cabecera se ignora: solo cuenta el del token', async () => {
  const m = await mundo();
  const antesBob = [instantanea(m, 'users/bob'), instantanea(m, 'coffeeLots/04')];
  const token = await firmarToken(m.claves, 'kid1', 'ana');
  const r = await handle(
    new Request('https://x.workers.dev/account-deletion/request?uid=bob', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'X-Uid': 'bob', 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid: 'bob', sub: 'bob', solicitadaAt: '2000-01-01T00:00:00Z', programadaAt: '2000-01-02T00:00:00Z', dias: 1, retencionDias: 1 }),
    }),
    ENVA, { fetch: m.fetch, nowMs: NOW_MS, idFn: m.idFn },
  );
  assert.equal(r.status, 200);
  assert.equal(m.leer('users/ana').cuentaEstado, 'eliminacionPendiente');
  assert.equal(m.docs.has('accountDeletionJobs/bob'), false);
  assert.deepEqual([instantanea(m, 'users/bob'), instantanea(m, 'coffeeLots/04')], antesBob);
  // fechas y días: solo los del servidor
  assert.equal(m.leer('accountDeletionJobs/ana').solicitadaAt, iso(NOW_MS));
  assert.equal(m.leer('accountDeletionJobs/ana').retencionDias, 15);
});

// ---------------------------------------------------------------------------------------------
// Solicitud: fechas, idempotencia, nueva solicitud tras cancelar
// ---------------------------------------------------------------------------------------------

test('la solicitud calcula exactamente 15 días desde el reloj del Worker y los guarda en el trabajo y en el usuario', async () => {
  const m = await mundo();
  const r = await solicitar(m, 'ana');
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { estado: 'eliminacionPendiente', solicitadaAt: iso(NOW_MS), programadaAt: iso(NOW_MS + 15 * DIA), retencionDias: 15, idempotente: false, cafesSuspendidos: 1 });
  const job = m.leer('accountDeletionJobs/ana');
  assert.equal(job.estado, 'pendiente');
  assert.equal(job.solicitudId, 'sol-1');
  assert.equal(job.solicitadaAt, iso(NOW_MS));
  assert.equal(job.programadaAt, iso(NOW_MS + 15 * DIA));
  assert.equal(job.retencionDias, 15);
  assert.equal(job.updatedAt, iso(NOW_MS));
  assert.equal('canceladaAt' in job, false);
  const user = m.leer('users/ana');
  assert.equal(user.cuentaEstado, 'eliminacionPendiente');
  assert.equal(user.eliminacionSolicitadaAt, iso(NOW_MS));
  assert.equal(user.eliminacionProgramadaAt, iso(NOW_MS + 15 * DIA));
  assert.equal(user.nombre, 'Ana'); // el resto del usuario no cambia
});

test('RETENCION_DIAS es configurable; un valor inválido es un error de configuración y no escribe nada', async () => {
  const m = await mundo();
  const r = await solicitar(m, 'ana', { env: await envConCuenta({ RETENCION_DIAS: '7' }) });
  assert.equal(r.json.programadaAt, iso(NOW_MS + 7 * DIA));
  assert.equal(retencionDias({}), 15);
  const m2 = await mundo();
  const antes = todas(m2);
  const mala = await solicitar(m2, 'ana', { env: await envConCuenta({ RETENCION_DIAS: 'quince' }) });
  assert.equal(mala.status, 500);
  assert.equal(todas(m2), antes);
});

test('solicitud duplicada: devuelve lo mismo, conserva la fecha original y no escribe', async () => {
  const m = await mundo();
  const primera = await solicitar(m, 'ana');
  const escrituras = m.escrituras.length;
  const jobAntes = instantanea(m, 'accountDeletionJobs/ana');
  const segunda = await solicitar(m, 'ana', { nowMs: NOW_MS + 3 * DIA });
  assert.equal(segunda.status, 200);
  assert.equal(segunda.json.idempotente, true);
  assert.equal(segunda.json.programadaAt, primera.json.programadaAt);
  assert.equal(segunda.json.solicitadaAt, primera.json.solicitadaAt);
  assert.equal(m.escrituras.length, escrituras);
  assert.equal(instantanea(m, 'accountDeletionJobs/ana'), jobAntes);
  assert.equal(m.idFn(), 'sol-2'); // el generador no se consumió en la segunda llamada
});

test('tras cancelar, una nueva solicitud crea otro solicitudId y un plazo nuevo de 15 días', async () => {
  const m = await mundo();
  await solicitar(m, 'ana');
  assert.equal((await cancelar(m, 'ana', { nowMs: NOW_MS + DIA })).status, 200);
  const nueva = await solicitar(m, 'ana', { nowMs: NOW_MS + 2 * DIA });
  assert.equal(nueva.status, 200);
  assert.equal(nueva.json.idempotente, false);
  assert.equal(nueva.json.programadaAt, iso(NOW_MS + 2 * DIA + 15 * DIA));
  const job = m.leer('accountDeletionJobs/ana');
  assert.equal(job.estado, 'pendiente');
  assert.equal(job.solicitudId, 'sol-2');
  assert.equal(job.solicitadaAt, iso(NOW_MS + 2 * DIA));
  assert.equal('canceladaAt' in job, false);
  assert.equal(m.leer('coffeeLots/01').suspensionSolicitudId, 'sol-2');
});

test('estados incompatibles (eliminando, desconocido, sin documento de usuario) no pueden iniciar ni cancelar', async () => {
  for (const cuenta of ['eliminando', 'otraCosa']) {
    const m = await mundo({ cuenta });
    const antes = todas(m);
    assert.equal((await solicitar(m, 'ana')).status, 409, cuenta);
    assert.equal((await cancelar(m, 'ana')).status, 409, cuenta);
    assert.equal(todas(m), antes);
  }
  const sinUsuario = await mundo();
  sinUsuario.docs.delete('users/ana');
  assert.equal((await solicitar(sinUsuario, 'ana')).status, 403);
  assert.equal((await cancelar(sinUsuario, 'ana')).status, 403);
  assert.equal(sinUsuario.docs.has('accountDeletionJobs/ana'), false);
});

test('usuarios antiguos sin cuentaEstado se tratan como activos', async () => {
  const m = await mundo(); // sin cuentaEstado
  assert.equal(m.leer('users/ana').cuentaEstado, undefined);
  assert.equal((await solicitar(m, 'ana')).status, 200);
});

// ---------------------------------------------------------------------------------------------
// Suspensión de cafés
// ---------------------------------------------------------------------------------------------

test('solo se suspenden los cafés PUBLICADOS del UID autenticado; el resto queda idéntico', async () => {
  const m = await mundo();
  const intactos = ['coffeeLots/02', 'coffeeLots/03', 'coffeeLots/04', 'sellerProfiles/ana', 'interestRequests/c1_01', 'quotes/q1', 'chats/c1_01/messages/m1', 'users/bob'];
  const antes = intactos.map((r) => instantanea(m, r));
  const fotos = m.leer('coffeeLots/01');
  const r = await solicitar(m, 'ana');
  assert.equal(r.json.cafesSuspendidos, 1);
  const c = m.leer('coffeeLots/01');
  assert.equal(c.estado, 'suspendido');
  assert.equal(c.estadoPrevio, 'publicado');
  assert.equal(c.suspensionSolicitudId, 'sol-1');
  // fotos, rutas y demás campos del café suspendido no cambian
  assert.deepEqual(c.fotos, fotos.fotos);
  assert.deepEqual(c.fotosStoragePaths, fotos.fotosStoragePaths);
  assert.equal(c.precioCOP, fotos.precioCOP);
  assert.deepEqual(intactos.map((r) => instantanea(m, r)), antes);
  // lo único escrito: trabajo, usuario y ese café
  assert.deepEqual(m.escrituras.map((e) => e.ruta).sort(), ['accountDeletionJobs/ana', 'coffeeLots/01', 'users/ana']);
  // y nada destructivo ni de ImageKit
  assert.equal(m.cuenta('borrarDoc'), 0);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.cuenta('imagekitDetalles'), 0);
});

test('un vendedor sin cafés publicados también puede solicitar', async () => {
  const m = await mundo({ conLotes: false });
  const r = await solicitar(m, 'ana');
  assert.equal(r.status, 200);
  assert.equal(r.json.cafesSuspendidos, 0);
});

test('con 498 cafés publicados cabe en un commit; con 499 se rechaza ANTES de modificar nada', async () => {
  const lleno = await mundo({ conLotes: false });
  for (let i = 0; i < MAX_CAFES; i++) lote(lleno, `a${i}`);
  const ok = await solicitar(lleno, 'ana');
  assert.equal(ok.status, 200);
  assert.equal(ok.json.cafesSuspendidos, MAX_CAFES);
  assert.equal(lleno.leer('users/ana').cuentaEstado, 'eliminacionPendiente');

  const demasiados = await mundo({ conLotes: false });
  for (let i = 0; i < MAX_CAFES + 1; i++) lote(demasiados, `a${i}`);
  const antes = todas(demasiados);
  const r = await solicitar(demasiados, 'ana');
  assert.equal(r.status, 409);
  assert.equal(r.json.codigo, 'limite_cafes');
  assert.equal(todas(demasiados), antes); // ni cuenta pendiente, ni trabajo, ni cafés suspendidos
  assert.equal(demasiados.cuenta('commit'), 0);
});

// ---------------------------------------------------------------------------------------------
// Cancelación
// ---------------------------------------------------------------------------------------------

test('cancelar antes del plazo restaura SOLO los cafés suspendidos por esa solicitud', async () => {
  const m = await mundo();
  await solicitar(m, 'ana');
  const intactos = ['coffeeLots/02', 'coffeeLots/03', 'coffeeLots/04', 'sellerProfiles/ana', 'interestRequests/c1_01', 'quotes/q1'];
  const antes = intactos.map((r) => instantanea(m, r));
  const r = await cancelar(m, 'ana', { nowMs: NOW_MS + 14 * DIA });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { estado: 'activa', idempotente: false, cafesRestaurados: 1 });
  const c = m.leer('coffeeLots/01');
  assert.equal(c.estado, 'publicado');
  assert.equal('estadoPrevio' in c, false);
  assert.equal('suspensionSolicitudId' in c, false);
  assert.equal(c.precioCOP, 32000);
  assert.deepEqual(intactos.map((x) => instantanea(m, x)), antes); // borrador, suspendido por otra causa, ajenos, historial
  const user = m.leer('users/ana');
  assert.equal(user.cuentaEstado, 'activa');
  assert.equal(user.eliminacionSolicitadaAt, null);
  assert.equal(user.eliminacionProgramadaAt, null);
  const job = m.leer('accountDeletionJobs/ana');
  assert.equal(job.estado, 'cancelado');
  assert.equal(job.canceladaAt, iso(NOW_MS + 14 * DIA));
  assert.equal(m.cuenta('borrarDoc'), 0);
});

test('un café que ya no sigue suspendido, o que otra solicitud suspendió, no se restaura', async () => {
  const m = await mundo();
  await solicitar(m, 'ana');
  m.poner('coffeeLots/09', { sellerId: 'ana', nombre: 'X', estado: 'suspendido', estadoPrevio: 'publicado', suspensionSolicitudId: 'otra-solicitud' });
  m.poner('coffeeLots/10', { sellerId: 'ana', nombre: 'Y', estado: 'borrador', suspensionSolicitudId: 'sol-1' }); // vuelto a borrador
  const antes = ['coffeeLots/09', 'coffeeLots/10'].map((r) => instantanea(m, r));
  const r = await cancelar(m, 'ana', { nowMs: NOW_MS + DIA });
  assert.equal(r.json.cafesRestaurados, 1);
  assert.deepEqual(['coffeeLots/09', 'coffeeLots/10'].map((x) => instantanea(m, x)), antes);
});

test('cancelar dos veces es idempotente: la segunda no escribe', async () => {
  const m = await mundo();
  await solicitar(m, 'ana');
  await cancelar(m, 'ana', { nowMs: NOW_MS + DIA });
  const escrituras = m.escrituras.length;
  const foto = todas(m);
  const otra = await cancelar(m, 'ana', { nowMs: NOW_MS + 2 * DIA });
  assert.equal(otra.status, 200);
  assert.deepEqual(otra.json, { estado: 'activa', idempotente: true, cafesRestaurados: 0 });
  assert.equal(m.escrituras.length, escrituras);
  assert.equal(todas(m), foto);
});

test('cancelar sin haber solicitado nada es un no-op seguro', async () => {
  const m = await mundo();
  const antes = todas(m);
  const r = await cancelar(m, 'ana');
  assert.equal(r.status, 200);
  assert.equal(r.json.idempotente, true);
  assert.equal(todas(m), antes);
});

test('cancelar con el plazo vencido (o justo en el límite) devuelve 409 y no modifica nada', async () => {
  const m = await mundo();
  await solicitar(m, 'ana');
  const antes = todas(m);
  for (const t of [NOW_MS + 15 * DIA, NOW_MS + 15 * DIA + 1, NOW_MS + 40 * DIA]) {
    resetLimitador();
    const r = await cancelar(m, 'ana', { nowMs: t });
    assert.equal(r.status, 409, String(t));
    assert.equal(r.json.codigo, 'plazo_vencido');
  }
  assert.equal(todas(m), antes);
  assert.equal(m.leer('coffeeLots/01').estado, 'suspendido');
});

// ---------------------------------------------------------------------------------------------
// Carreras, precondiciones y errores temporales
// ---------------------------------------------------------------------------------------------

test('carrera: un café publicado aparece entre la lectura y el commit → se relee y se suspende también', async () => {
  const m = await mundo();
  let n = 0;
  m.antesDeCommit = () => {
    if (n++ === 0) lote(m, '55'); // otro dispositivo publica un café justo ahora
    return null;
  };
  const r = await solicitar(m, 'ana');
  assert.equal(r.status, 200);
  assert.equal(m.cuenta('commit'), 2); // el primero se abortó, el segundo se aplicó
  assert.equal(r.json.cafesSuspendidos, 2);
  assert.equal(m.leer('coffeeLots/01').estado, 'suspendido');
  assert.equal(m.leer('coffeeLots/55').estado, 'suspendido');
  assert.equal(m.leer('users/ana').cuentaEstado, 'eliminacionPendiente');
});

test('carrera: un documento leído cambia antes del commit → no hay estado parcial', async () => {
  const m = await mundo();
  let n = 0;
  m.antesDeCommit = () => {
    // la cuenta cambia de estado entre la lectura y el commit, SIEMPRE
    n++;
    m.poner('users/ana', { uid: 'ana', email: 'ana@x.co', rol: 'vendedor', nombre: `Ana ${n}` });
    return null;
  };
  const r = await solicitar(m, 'ana');
  assert.equal(r.status, 503);
  assert.equal(r.json.codigo, 'temporal');
  assert.equal(m.cuenta('commit'), 3); // MAX_INTENTOS_TX
  assert.equal(m.docs.has('accountDeletionJobs/ana'), false);
  assert.equal(m.leer('users/ana').cuentaEstado, undefined);
  assert.equal(m.leer('coffeeLots/01').estado, 'publicado');
});

test('dos solicitudes simultáneas no crean dos periodos', async () => {
  const m = await mundo();
  const [a, b] = await Promise.all([solicitar(m, 'ana'), solicitar(m, 'ana', { nowMs: NOW_MS })]);
  assert.deepEqual([a.status, b.status], [200, 200]);
  const job = m.leer('accountDeletionJobs/ana');
  assert.equal(job.estado, 'pendiente');
  assert.equal(m.leer('coffeeLots/01').suspensionSolicitudId, job.solicitudId);
  assert.equal(a.json.programadaAt, b.json.programadaAt);
  assert.equal(m.escrituras.filter((e) => e.ruta === 'accountDeletionJobs/ana').length, 1);
});

test('un commit que falla (500) no deja escrituras parciales y se informa como temporal', async () => {
  const m = await mundo();
  m.fallos.firestoreCommit = [500];
  const antes = todas(m);
  const r = await solicitar(m, 'ana');
  assert.equal(r.status, 503);
  assert.equal(todas(m), antes);
  // reintentar después funciona y no duplica
  const ok = await solicitar(m, 'ana');
  assert.equal(ok.status, 200);
  assert.equal(ok.json.idempotente, false);
});

test('errores temporales de Firestore (consulta, inicio de transacción) y de las claves de Firebase → 503', async () => {
  const m = await mundo();
  m.fallos.firestoreConsulta = [500];
  assert.equal((await solicitar(m, 'ana')).status, 503);
  m.fallos.firestoreBeginTx = [503];
  resetLimitador();
  assert.equal((await solicitar(m, 'ana')).status, 503);
  assert.equal(m.docs.has('accountDeletionJobs/ana'), false);

  const sinClaves = await mundo();
  const r = await solicitar(sinClaves, 'ana', { fetchFn: (url, init) => (String(url).includes('/robot/v1/metadata/jwk') ? Promise.reject(new TypeError('red')) : sinClaves.fetch(url, init)) });
  assert.equal(r.status, 503);
});

// ---------------------------------------------------------------------------------------------
// Rutas, métodos, límite de llamadas, configuración y barrera DRY_RUN
// ---------------------------------------------------------------------------------------------

test('rutas desconocidas, métodos incorrectos y HTTP plano', async () => {
  const m = await mundo();
  assert.equal((await pedir(m, '/account-deletion/otra', 'ana')).status, 404);
  assert.equal((await pedir(m, '/account-deletion', 'ana')).status, 404);
  assert.equal((await pedir(m, '/account-deletion/request', 'ana', { metodo: 'GET' })).status, 405);
  assert.equal((await pedir(m, '/account-deletion/cancel', 'ana', { metodo: 'DELETE' })).status, 405);
  assert.equal((await pedir(m, '/account-deletion/request', 'ana', { url: 'http://x.workers.dev/account-deletion/request' })).status, 400);
  assert.equal(m.docs.has('accountDeletionJobs/ana'), false);
});

test('límite de llamadas propio de las rutas de cuenta (429), sin afectar a POST /', async () => {
  const m = await mundo();
  for (let i = 0; i < 10; i++) assert.equal((await cancelar(m, 'ana', { nowMs: NOW_MS + i })).status, 200, `llamada ${i}`);
  const r = await cancelar(m, 'ana', { nowMs: NOW_MS + 11 });
  assert.equal(r.status, 429);
  // otra persona no se ve afectada
  assert.equal((await cancelar(m, 'bob')).status, 200);
  // la ruta de limpieza conserva su propio límite y sigue funcionando
  const token = await firmarToken(m.claves, 'kid1', 'ana');
  const limpieza = await handle(new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }), ENVA, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(limpieza.status, 200);
});

test('configuración separada: las rutas de cuenta no necesitan la clave de ImageKit; la limpieza sí', async () => {
  const m = await mundo();
  const { IMAGEKIT_PRIVATE_KEY, ...sinImageKit } = ENVA;
  assert.ok(IMAGEKIT_PRIVATE_KEY);
  assert.equal((await solicitar(m, 'ana', { env: sinImageKit })).status, 200);
  const token = await firmarToken(m.claves, 'kid1', 'ana');
  const limpieza = await handle(new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }), sinImageKit, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(limpieza.status, 500);
  const { CLEANUP_SERVICE_ACCOUNT_JSON, ...sinCuenta } = ENVA;
  assert.ok(CLEANUP_SERVICE_ACCOUNT_JSON);
  assert.equal((await cancelar(m, 'ana', { env: sinCuenta })).status, 500);
});

test('DRY_RUN: aunque diga «false», la etapa 6 no ejecuta nada destructivo', async () => {
  assert.equal(BORRADO_DEFINITIVO_IMPLEMENTADO, false);
  for (const valor of ['true', 'false', undefined, 'cualquier-cosa']) assert.equal(dryRunActivo({ DRY_RUN: valor }), true);
  const m = await mundo();
  m.archivo('5f8a1c2b3d4e5f6a7b8c9d01', '/lotea-cafe/users/ana/lots/01.jpg');
  const env = await envConCuenta({ DRY_RUN: 'false' });
  await solicitar(m, 'ana', { env });
  await cancelar(m, 'ana', { env, nowMs: NOW_MS + DIA });
  await solicitar(m, 'ana', { env, nowMs: NOW_MS + 2 * DIA });
  assert.equal(m.cuenta('borrarDoc'), 0);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.archivos.size, 1); // la foto sigue en ImageKit
  assert.ok(m.escrituras.every((e) => !e.campos.includes('*borrado*')));
  assert.ok(m.docs.has('users/ana') && m.docs.has('sellerProfiles/ana') && m.docs.has('interestRequests/c1_01') && m.docs.has('quotes/q1'));
});

test('el código de cuentas no contiene operaciones de borrado ni llamadas a ImageKit', async () => {
  const { readFileSync } = await import('node:fs');
  for (const f of ['../src/account-deletion.js', '../src/firestore-tx.js']) {
    const codigo = readFileSync(new URL(f, import.meta.url), 'utf8').replace(/\/\/.*$/gm, '');
    assert.ok(!/method:\s*'DELETE'/.test(codigo), f);
    assert.ok(!/imagekit/i.test(codigo), f);
    assert.ok(!/\bdelete\s*:/.test(codigo), f); // ni `delete` de escritura de commit
  }
});
