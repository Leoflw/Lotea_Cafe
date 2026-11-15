// Pruebas del Worker de limpieza con `node --test` (Node 20+). Todo el entorno
// (Firestore, ImageKit, OAuth, claves de Firebase) está simulado en memoria.
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { handle, barrido, resetLimitador, MAX_POR_EJECUCION } from '../src/index.js';
import { resetJwksCache } from '../src/firebase.js';
import { resetAuthCache, leerCuentaDeServicio, obtenerAccessToken } from '../src/google-auth.js';
import { esDelUsuario, esperaTrasIntento, MAX_INTENTOS } from '../src/cleanup.js';
import { ENV, NOW_MS, RAIZ, mundoConClaves, tokenDe } from './backend-falso.js';

const FID = '5f8a1c2b3d4e5f6a7b8c9d01'; // 24 caracteres, como un fileId de ImageKit
const FID2 = '5f8a1c2b3d4e5f6a7b8c9d02';
const rutaCola = (uid, id) => `users/${uid}/pendingFileDeletions/${id}`;
const rutaImg = (uid, carpeta = 'lots', nombre = 'lot_1.jpg') => `${RAIZ}/users/${uid}/${carpeta}/${nombre}`;

beforeEach(() => {
  resetLimitador();
  resetJwksCache();
  resetAuthCache();
});

async function llamar(mundo, uid, { nowMs = NOW_MS, token } = {}) {
  const t = token ?? (await tokenDe(mundo, uid, nowMs));
  const req = new Request('https://cleanup.example.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${t}` } });
  // El access token de la cuenta de servicio se simula: se evita firmar con RSA real.
  return handle(req, ENVR, { fetch: mundo.fetch, nowMs });
}

// google-auth usa la cuenta real; en estas pruebas se reemplaza por una clave generada.
async function envConCuentaReal() {
  const par = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', par.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return { ...ENV, CLEANUP_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'limpieza@lotea-cafe.iam.gserviceaccount.com', private_key: pem, project_id: 'lotea-cafe' }) };
}

const ENVR = await envConCuentaReal();

test('flujo feliz: borra una foto propia sin referencias y marca la solicitud completada', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  const r = await handle(new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${await tokenDe(m, 'ana')}` } }), ENVR, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(r.status, 200);
  const cuerpo = await r.json();
  assert.equal(cuerpo.completadas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 1);
  assert.equal(m.archivos.has(FID), false);
  const cola = m.leer(rutaCola('ana', FID));
  assert.equal(cola.estado, 'completado');
  assert.equal(cola.leaseUntil, undefined);
  assert.match(m.llamadas.find((l) => l.tipo === 'imagekitBorrar').auth, /^Basic /);
});

test('NO borra una foto que un lote todavía referencia (por fileId)', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.poner('coffeeLots/l1', { sellerId: 'ana', fotos: ['otra'], fotosStoragePaths: [FID] });
  m.cola('ana', FID);
  const cuerpo = await (await llamar(m, 'ana')).json();
  assert.equal(cuerpo.enUso, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.ok(m.archivos.has(FID));
  assert.equal(m.leer(rutaCola('ana', FID)).estado, 'enUso');
});

test('NO borra si un lote la referencia solo por URL (documento antiguo sin fileId)', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.poner('coffeeLots/l1', { sellerId: 'ana', fotos: [m.archivos.get(FID).url], fotosStoragePaths: [''] });
  m.cola('ana', FID);
  assert.equal((await (await llamar(m, 'ana')).json()).enUso, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
});

test('NO borra la foto principal ni las de galería de un perfil', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana', 'profile', 'p1.jpg'));
  m.archivo(FID2, rutaImg('ana', 'profile', 'p2.jpg'));
  m.poner('sellerProfiles/ana', { fotoPrincipalStoragePath: FID, galeriaStoragePaths: [FID2], fotoPrincipal: 'u1', galeria: ['u2'] });
  m.cola('ana', FID, { origen: 'profile' });
  m.cola('ana', FID2, { origen: 'profile' });
  const cuerpo = await (await llamar(m, 'ana')).json();
  assert.equal(cuerpo.enUso, 2);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
});

test('sustitución: la foto vieja se borra y la nueva (referenciada) se conserva', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana', 'lots', 'vieja.jpg'));
  m.archivo(FID2, rutaImg('ana', 'lots', 'nueva.jpg'));
  m.poner('coffeeLots/l1', { sellerId: 'ana', fotos: ['n'], fotosStoragePaths: [FID2] }); // ya guarda la nueva
  m.cola('ana', FID); // se pidió borrar la vieja
  const cuerpo = await (await llamar(m, 'ana')).json();
  assert.equal(cuerpo.completadas, 1);
  assert.equal(m.archivos.has(FID), false);
  assert.equal(m.archivos.has(FID2), true);
});

test('archivo de OTRO usuario: se rechaza y no se borra', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('beto')); // pertenece a beto
  m.cola('ana', FID); // ana intenta borrarlo
  const cuerpo = await (await llamar(m, 'ana')).json();
  assert.equal(cuerpo.rechazadas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.ok(m.archivos.has(FID));
  const cola = m.leer(rutaCola('ana', FID));
  assert.equal(cola.estado, 'rechazado');
  assert.equal(cola.motivo, 'no_es_del_usuario');
});

test('rutas engañosas no pasan: otra raíz, otro uid con el mismo prefijo, carpeta desconocida, ..', () => {
  assert.equal(esDelUsuario(`${RAIZ}/users/ana/lots/a.jpg`, 'ana', RAIZ), true);
  assert.equal(esDelUsuario(`${RAIZ}/users/ana/profile/a.jpg`, 'ana', `${RAIZ}/`), true);
  assert.equal(esDelUsuario(`${RAIZ}/users/anabel/lots/a.jpg`, 'ana', RAIZ), false);
  assert.equal(esDelUsuario(`/otra/users/ana/lots/a.jpg`, 'ana', RAIZ), false);
  assert.equal(esDelUsuario(`${RAIZ}/users/ana/secretos/a.jpg`, 'ana', RAIZ), false);
  assert.equal(esDelUsuario(`${RAIZ}/users/ana/lots/../../beto/lots/a.jpg`, 'ana', RAIZ), false);
  assert.equal(esDelUsuario(`${RAIZ}/users/ana/lots/`, 'ana', RAIZ), false);
  assert.equal(esDelUsuario(undefined, 'ana', RAIZ), false);
});

test('un usuario solo procesa SU cola: el token de beto no toca la solicitud de ana', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  const cuerpo = await (await llamar(m, 'beto')).json();
  assert.equal(cuerpo.procesadas, 0);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.leer(rutaCola('ana', FID)).estado, 'pendiente');
});

test('idempotencia: repetir la llamada no vuelve a borrar ni daña nada', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  await llamar(m, 'ana');
  const segunda = await (await llamar(m, 'ana')).json();
  assert.equal(segunda.procesadas, 0); // completado ya no es procesable
  assert.equal(m.cuenta('imagekitBorrar'), 1);
  assert.equal(m.leer(rutaCola('ana', FID)).estado, 'completado');
});

test('si ImageKit ya no tiene el archivo (404) la solicitud queda completada sin llamar a borrar', async () => {
  const m = await mundoConClaves();
  m.cola('ana', FID); // el archivo no existe
  const cuerpo = await (await llamar(m, 'ana')).json();
  assert.equal(cuerpo.completadas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.leer(rutaCola('ana', FID)).motivo, 'ya_no_existia');
});

test('error temporal de ImageKit al borrar: queda errorTemporal con espera y se reintenta después', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  m.fallos.imagekitBorrar = [503];
  const r1 = await (await llamar(m, 'ana')).json();
  assert.equal(r1.reintentos, 1);
  const c1 = m.leer(rutaCola('ana', FID));
  assert.equal(c1.estado, 'errorTemporal');
  assert.equal(c1.intentos, 1);
  assert.equal(c1.ultimoError, 'imagekit_5xx');
  assert.ok(Date.parse(c1.nextAttemptAt) > NOW_MS);
  assert.ok(m.archivos.has(FID));

  // Antes de cumplirse la espera no se toca.
  const r2 = await (await llamar(m, 'ana', { nowMs: NOW_MS + 60_000 })).json();
  assert.equal(r2.procesadas, 0);

  // Pasada la espera, se reintenta y se completa.
  const r3 = await (await llamar(m, 'ana', { nowMs: NOW_MS + esperaTrasIntento(1) + 1000 })).json();
  assert.equal(r3.completadas, 1);
  assert.equal(m.archivos.has(FID), false);
});

test('error de red y 429 de ImageKit también son temporales', async () => {
  for (const f of ['red', 429]) {
    const m = await mundoConClaves();
    resetLimitador();
    resetJwksCache(); // cada mundo tiene sus propias claves
    m.archivo(FID, rutaImg('ana'));
    m.cola('ana', FID);
    m.fallos.imagekitDetalles = [f];
    const r = await (await llamar(m, 'ana')).json();
    assert.equal(r.reintentos, 1, `fallo ${f}`);
    assert.ok(m.archivos.has(FID));
  }
});

test('tras MAX_INTENTOS errores seguidos queda «fallido» y deja de reintentarse', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  let ahora = NOW_MS;
  for (let i = 1; i <= MAX_INTENTOS; i++) {
    m.fallos.imagekitBorrar = [500];
    await llamar(m, 'ana', { nowMs: ahora });
    ahora += esperaTrasIntento(i) + 1000;
    resetLimitador();
  }
  const c = m.leer(rutaCola('ana', FID));
  assert.equal(c.estado, 'fallido');
  assert.equal(c.intentos, MAX_INTENTOS);
  const r = await (await llamar(m, 'ana', { nowMs: ahora })).json();
  assert.equal(r.procesadas, 0);
  assert.ok(m.archivos.has(FID));
});

test('FALLA CERRADO: si la consulta de referencias falla, NO se borra', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  m.fallos.firestoreConsulta = [500];
  const r = await (await llamar(m, 'ana')).json();
  assert.equal(r.reintentos, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.ok(m.archivos.has(FID));
  assert.match(m.leer(rutaCola('ana', FID)).ultimoError, /^firestore_referencias/);
});

test('un fileId con forma inválida se rechaza sin llamar a ImageKit', async () => {
  const m = await mundoConClaves();
  m.cola('ana', 'corto');
  const r = await (await llamar(m, 'ana')).json();
  assert.equal(r.rechazadas, 1);
  assert.equal(m.cuenta('imagekitDetalles'), 0);
});

test('lease vigente: una solicitud «procesando» de otra ejecución se omite; vencida se retoma', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID, { estado: 'procesando', leaseUntil: null });
  m.docs.get(rutaCola('ana', FID)).fields.leaseUntil = { timestampValue: new Date(NOW_MS + 60_000).toISOString() };
  assert.equal((await (await llamar(m, 'ana')).json()).procesadas, 0);
  resetLimitador();
  const r = await (await llamar(m, 'ana', { nowMs: NOW_MS + 5 * 60_000 })).json();
  assert.equal(r.completadas, 1);
});

test('carrera: si el documento cambió entre la lectura y el reclamo, se omite sin borrar', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  const original = m.fetch;
  let tocado = false;
  m.fetch = async (url, init) => {
    if (!tocado && (init?.method || 'GET') === 'GET' && String(url).includes('pendingFileDeletions')) {
      const r = await original(url, init);
      tocado = true;
      m.docs.get(rutaCola('ana', FID)).updateTime = 'cambiado-por-otra-ejecucion';
      return r;
    }
    return original(url, init);
  };
  const r = await (await llamar(m, 'ana')).json();
  assert.equal(r.omitidas, 1);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
});

test('máximo por ejecución: respeta el límite de subpeticiones y avisa de lo que queda', async () => {
  const m = await mundoConClaves();
  for (let i = 0; i < MAX_POR_EJECUCION + 3; i++) {
    const id = `5f8a1c2b3d4e5f6a7b8c9d${String(i).padStart(2, '0')}`;
    m.archivo(id, rutaImg('ana', 'lots', `f${i}.jpg`));
    m.cola('ana', id);
  }
  const r = await (await llamar(m, 'ana')).json();
  assert.equal(r.procesadas, MAX_POR_EJECUCION);
  assert.equal(r.restantes, 3);
});

test('autenticación: sin token, token de otro proyecto o manipulado → 401 sin tocar nada', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.cola('ana', FID);
  const sin = await handle(new Request('https://x.workers.dev/', { method: 'POST' }), ENVR, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(sin.status, 401);
  const ajeno = await tokenDe(m, 'ana').then(() => import('./backend-falso.js').then((b) => b.firmarToken(m.claves, 'kid1', 'ana', { aud: 'otro-proyecto' })));
  assert.equal((await llamar(m, 'ana', { token: ajeno })).status, 401);
  const t = await tokenDe(m, 'ana');
  const roto = `${t.slice(0, -4)}AAAA`;
  assert.equal((await llamar(m, 'ana', { token: roto })).status, 401);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
  assert.equal(m.leer(rutaCola('ana', FID)).estado, 'pendiente');
});

test('solo POST en «/», HTTPS obligatorio y configuración completa', async () => {
  const m = await mundoConClaves();
  const base = { fetch: m.fetch, nowMs: NOW_MS };
  assert.equal((await handle(new Request('https://x.workers.dev/', { method: 'GET' }), ENVR, base)).status, 405);
  assert.equal((await handle(new Request('https://x.workers.dev/otra', { method: 'POST' }), ENVR, base)).status, 404);
  assert.equal((await handle(new Request('http://x.workers.dev/', { method: 'POST' }), ENVR, base)).status, 400);
  const sinSecreto = { ...ENVR, IMAGEKIT_PRIVATE_KEY: '' };
  assert.equal((await handle(new Request('https://x.workers.dev/', { method: 'POST' }), sinSecreto, base)).status, 500);
});

test('el cuerpo de la petición se ignora: un fileId enviado por el cliente no se usa', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  const t = await tokenDe(m, 'ana');
  const req = new Request('https://x.workers.dev/', { method: 'POST', headers: { Authorization: `Bearer ${t}` }, body: JSON.stringify({ fileId: FID }) });
  const r = await (await handle(req, ENVR, { fetch: m.fetch, nowMs: NOW_MS })).json();
  assert.equal(r.procesadas, 0);
  assert.equal(m.cuenta('imagekitBorrar'), 0);
});

test('barrido (cron): reintenta las colas de varios usuarios', async () => {
  const m = await mundoConClaves();
  m.archivo(FID, rutaImg('ana'));
  m.archivo(FID2, rutaImg('beto', 'profile', 'p.jpg'));
  m.cola('ana', FID);
  m.cola('beto', FID2, { origen: 'profile', estado: 'errorTemporal', nextAttemptAt: null });
  m.docs.get(rutaCola('beto', FID2)).fields.nextAttemptAt = { timestampValue: new Date(NOW_MS - 1000).toISOString() };
  const r = await barrido(ENVR, { fetch: m.fetch, nowMs: NOW_MS });
  assert.equal(r.completadas, 2);
  assert.equal(m.archivos.size, 0);
});

test('cuenta de servicio: alcance único de Firestore y rechazo de cuentas de otro proyecto', async () => {
  const env = await envConCuentaReal();
  let cuerpoToken;
  const fetchFn = async (url, init) => {
    cuerpoToken = new URLSearchParams(init.body).get('assertion');
    return new Response(JSON.stringify({ access_token: 'abc', expires_in: 3600 }), { status: 200 });
  };
  assert.equal(await obtenerAccessToken(env, { fetchFn, nowMs: NOW_MS }), 'abc');
  const claims = JSON.parse(Buffer.from(cuerpoToken.split('.')[1], 'base64url').toString());
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/datastore');
  assert.throws(() => leerCuentaDeServicio(env.CLEANUP_SERVICE_ACCOUNT_JSON, 'otro-proyecto'), (e) => e.codigo === 'cuenta_otro_proyecto');
});
