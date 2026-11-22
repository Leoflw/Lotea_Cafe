// Pruebas REALES de firestore.rules contra el emulador de Firestore (etapa 6: eliminación de cuenta).
// Ejecutar desde esta carpeta (necesita Java y firebase-tools):  npm install && npm test
//
// Cuentas de prueba (todas con documento users/{uid}):
//   ana    vendedora ANTIGUA: sin el campo cuentaEstado (debe tratarse como activa)
//   sel    vendedor con cuentaEstado: 'activa'
//   pend   vendedor con cuentaEstado: 'eliminacionPendiente'
//   raro   vendedor con un cuentaEstado desconocido ('eliminando')
//   comp, comp3   compradores activos
//   cpend  comprador con eliminación pendiente
//
// Cada «bloqueo» de una cuenta pendiente va acompañado de un CONTROL que sí pasa con una cuenta
// activa: así se demuestra que lo que bloquea es el estado de la cuenta y no un campo mal formado.
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, query, where, writeBatch, serverTimestamp, deleteField,
} from 'firebase/firestore';
import { loteReal, perfilReal } from './fixtures.js';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'lotea-cafe-test-account-lifecycle', // propio de este archivo (ver chat_state.rules.test.js)
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env.cleanup());

const AHORA = new Date('2026-11-14T12:00:00Z');
const PROGRAMADA = new Date('2026-11-29T12:00:00Z');
const dbDe = (uid, claims = {}) => env.authenticatedContext(uid, claims).firestore();

const solicitudBase = (comprador, seller, lot, estado) => ({
  compradorId: comprador, sellerId: seller, coffeeLotId: lot, estado, mensaje: null,
  compradorNombre: 'C', sellerNombre: 'S', loteNombre: 'L', loteFoto: null, lotePrecioCOP: 32000, loteUnidad: 'kg',
  createdAt: AHORA, updatedAt: AHORA,
});
const cotizacionBase = (solicitud, comprador, seller, lot, estado = 'solicitudPendiente') => ({
  interestRequestId: solicitud, compradorId: comprador, sellerId: seller, coffeeLotId: lot, cantidad: 10, unidad: 'kg',
  estado, oferta: null, revisionComentario: null, createdAt: AHORA, updatedAt: AHORA,
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const poner = (ruta, datos) => setDoc(doc(db, ruta), datos);
    // usuarios
    await poner('users/ana', { rol: 'vendedor', nombre: 'Ana', email: 'ana@x.co' }); // antigua: SIN cuentaEstado
    await poner('users/sel', { rol: 'vendedor', nombre: 'Sel', email: 'sel@x.co', cuentaEstado: 'activa' });
    await poner('users/pend', {
      rol: 'vendedor', nombre: 'Pend', email: 'pend@x.co', cuentaEstado: 'eliminacionPendiente',
      eliminacionSolicitadaAt: AHORA, eliminacionProgramadaAt: PROGRAMADA,
    });
    await poner('users/raro', { rol: 'vendedor', nombre: 'Raro', email: 'raro@x.co', cuentaEstado: 'eliminando' });
    await poner('users/comp', { rol: 'comprador', nombre: 'Comp', email: 'comp@x.co' });
    await poner('users/comp3', { rol: 'comprador', nombre: 'Comp3', email: 'comp3@x.co', cuentaEstado: 'activa' });
    await poner('users/cpend', { rol: 'comprador', nombre: 'CPend', email: 'cpend@x.co', cuentaEstado: 'eliminacionPendiente' });
    // perfiles de vendedor
    for (const id of ['ana', 'sel', 'pend', 'raro']) await poner(`sellerProfiles/${id}`, perfilReal({ usuarioId: id }));
    // cafés
    await poner('coffeeLots/loteAna', loteReal({ sellerId: 'ana' }));
    await poner('coffeeLots/loteSel', loteReal({ sellerId: 'sel' }));
    await poner('coffeeLots/pendPub', loteReal({ sellerId: 'pend' })); // publicado (p. ej. antes de que el Worker lo suspenda)
    await poner('coffeeLots/pendBorrador', loteReal({ sellerId: 'pend', estado: 'borrador', fechaPublicacion: null }));
    await poner('coffeeLots/pendSusp', loteReal({ sellerId: 'pend', estado: 'suspendido', estadoPrevio: 'publicado', suspensionSolicitudId: 's1' }));
    await poner('coffeeLots/selSusp', loteReal({ sellerId: 'sel', estado: 'suspendido', estadoPrevio: 'publicado', suspensionSolicitudId: 's2' }));
    await poner('coffeeLots/raroLote', loteReal({ sellerId: 'raro' }));
    // solicitudes de interés
    await poner('interestRequests/pend_ana', solicitudBase('comp', 'ana', 'loteAna', 'pendiente'));
    await poner('interestRequests/pend_sel', solicitudBase('comp', 'sel', 'loteSel', 'pendiente'));
    await poner('interestRequests/pend_deCpend', solicitudBase('cpend', 'ana', 'loteAna', 'pendiente'));
    await poner('interestRequests/pend_dePend', solicitudBase('comp', 'pend', 'pendPub', 'pendiente'));
    await poner('interestRequests/ok_ana', solicitudBase('comp', 'ana', 'loteAna', 'aceptada'));
    await poner('interestRequests/ok_sel', solicitudBase('comp', 'sel', 'loteSel', 'aceptada'));
    await poner('interestRequests/ok_pend', solicitudBase('comp', 'pend', 'pendPub', 'aceptada'));
    await poner('interestRequests/ok_cpend', solicitudBase('cpend', 'ana', 'loteAna', 'aceptada'));
    await poner('interestRequests/rech_ana', solicitudBase('comp', 'ana', 'loteAna', 'rechazada'));
    await poner('interestRequests/rech_pend', solicitudBase('comp', 'pend', 'pendPub', 'rechazada'));
    await poner('interestRequests/rech_deCpend', solicitudBase('cpend', 'ana', 'loteAna', 'rechazada'));
    // chats
    for (const c of ['ok_ana', 'ok_sel', 'ok_pend', 'ok_cpend']) await poner(`chats/${c}/messages/m0`, { senderId: 'comp', texto: 'hola', createdAt: AHORA });
    // cotizaciones y su historial
    await poner('quotes/qAna', cotizacionBase('ok_ana', 'comp', 'ana', 'loteAna'));
    await poner('quotes/qSel', cotizacionBase('ok_sel', 'comp', 'sel', 'loteSel'));
    await poner('quotes/qPend', cotizacionBase('ok_pend', 'comp', 'pend', 'pendPub'));
    await poner('quotes/qCpend', cotizacionBase('ok_cpend', 'cpend', 'ana', 'loteAna'));
    await poner('quotes/qPend/events/e0', { tipo: 'solicitudCreada', actor: 'comprador', actorId: 'comp', fecha: AHORA });
    // trabajo interno del Worker
    await poner('accountDeletionJobs/pend', { estado: 'pendiente', solicitudId: 's1', solicitadaAt: AHORA, programadaAt: PROGRAMADA, retencionDias: 15 });
    await poner('accountDeletionJobs/pend/detalle/x', { dato: 1 });
  });
});

const lote = (db, id) => doc(db, 'coffeeLots', id);
const solicitud = (db, id) => doc(db, 'interestRequests', id);
const cotizacion = (db, id) => doc(db, 'quotes', id);
const leerSinReglas = async (ruta) => {
  let datos;
  await env.withSecurityRulesDisabled(async (ctx) => { datos = (await getDoc(doc(ctx.firestore(), ruta))).data(); });
  return datos;
};
const ediciones = () => ({ nombre: 'Nombre nuevo', updatedAt: serverTimestamp() });

const loteNuevo = (uid) => loteReal({
  sellerId: uid, estado: 'borrador', fechaPublicacion: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});
const solicitudNueva = (comprador, seller, lot) => ({
  compradorId: comprador, sellerId: seller, coffeeLotId: lot, mensaje: null, estado: 'pendiente',
  compradorNombre: 'C', compradorCiudad: null, compradorTipo: null, sellerNombre: 'S', loteNombre: 'L',
  loteFoto: null, lotePrecioCOP: 32000, loteUnidad: 'kg', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});
const cotizacionNueva = (solicitudId, comprador, seller, lot) => ({
  interestRequestId: solicitudId, compradorId: comprador, sellerId: seller, coffeeLotId: lot, cantidad: 5, unidad: 'kg',
  comentario: null, lugarEntrega: null, estado: 'solicitudPendiente', oferta: null, revisionComentario: null,
  compradorNombre: 'C', sellerNombre: 'S', loteNombre: 'L', loteFoto: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});

// ---- 1. Usuario antiguo (sin cuentaEstado) y 2. cuenta activa: todo sigue como antes ----

for (const [titulo, uid] of [['1. usuaria antigua SIN cuentaEstado', 'ana'], ['2. cuenta con cuentaEstado «activa»', 'sel']]) {
  const suyo = uid === 'ana' ? 'loteAna' : 'loteSel';
  const compradorDe = uid === 'ana' ? 'pend_ana' : 'pend_sel';

  test(`${titulo}: edita su café y su perfil de marca`, async () => {
    const db = dbDe(uid);
    await assertSucceeds(updateDoc(lote(db, suyo), ediciones()));
    await assertSucceeds(updateDoc(doc(db, 'sellerProfiles', uid), { nombreMarca: 'Marca nueva', updatedAt: serverTimestamp() }));
  });

  test(`${titulo}: crea un café en borrador`, async () => {
    await assertSucceeds(setDoc(doc(dbDe(uid), 'coffeeLots', 'nuevoCafe'), loteNuevo(uid)));
  });

  test(`${titulo}: responde una solicitud de interés`, async () => {
    await assertSucceeds(updateDoc(solicitud(dbDe(uid), compradorDe), { estado: 'aceptada', updatedAt: serverTimestamp() }));
  });

  test(`${titulo}: puede pedir eliminar un café (cola de eliminación de lotes)`, async () => {
    await assertSucceeds(setDoc(doc(dbDe(uid), 'users', uid, 'pendingLotDeletions', suyo), { lotId: suyo, estado: 'pendiente', createdAt: serverTimestamp() }));
  });
}

test('1/2. un comprador activo sigue pudiendo solicitar contacto, escribir en el chat y pedir cotización', async () => {
  const db = dbDe('comp3');
  await assertSucceeds(setDoc(solicitud(db, 'comp3_loteSel'), solicitudNueva('comp3', 'sel', 'loteSel')));
  await assertSucceeds(setDoc(doc(dbDe('comp'), 'chats', 'ok_sel', 'messages', 'nuevo'), { senderId: 'comp', texto: 'Hola', createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(cotizacion(dbDe('comp'), 'qNueva'), cotizacionNueva('ok_sel', 'comp', 'sel', 'loteSel')));
});

test('1/2. el vendedor activo responde una cotización y escribe su historial en el mismo lote', async () => {
  const db = dbDe('sel');
  const lote1 = writeBatch(db);
  lote1.update(cotizacion(db, 'qSel'), { estado: 'solicitudRechazada', updatedAt: serverTimestamp() });
  lote1.set(doc(db, 'quotes', 'qSel', 'events', 'e1'), { tipo: 'solicitudRechazada', actor: 'vendedor', actorId: 'sel', fecha: serverTimestamp() });
  await assertSucceeds(lote1.commit());
});

// ---- 3. Una cuenta pendiente no puede operar comercialmente ----

test('3. cuenta pendiente NO puede editar ni publicar cafés (publicado, borrador ni suspendido)', async () => {
  const db = dbDe('pend');
  await assertFails(updateDoc(lote(db, 'pendPub'), ediciones()));
  await assertFails(updateDoc(lote(db, 'pendBorrador'), ediciones()));
  await assertFails(updateDoc(lote(db, 'pendBorrador'), { estado: 'publicado', fechaPublicacion: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(lote(db, 'pendSusp'), ediciones()));
  await assertFails(updateDoc(lote(db, 'pendSusp'), { estado: 'publicado', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(lote(db, 'pendSusp'), { estado: 'borrador', updatedAt: serverTimestamp() }));
  // control: el mismo cambio sobre un café de una cuenta activa SÍ pasa
  await assertSucceeds(updateDoc(lote(dbDe('sel'), 'loteSel'), ediciones()));
});

test('3. cuenta pendiente NO puede crear cafés ni tocar su perfil de marca', async () => {
  const db = dbDe('pend');
  await assertFails(setDoc(doc(db, 'coffeeLots', 'nuevoCafe'), loteNuevo('pend')));
  await assertFails(updateDoc(doc(db, 'sellerProfiles', 'pend'), { nombreMarca: 'Otra', updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(dbDe('sel'), 'coffeeLots', 'nuevoCafe'), loteNuevo('sel'))); // control
});

test('3. cuenta pendiente NO puede pedir eliminar un café (los suspendidos se conservan)', async () => {
  const db = dbDe('pend');
  await assertFails(setDoc(doc(db, 'users', 'pend', 'pendingLotDeletions', 'pendSusp'), { lotId: 'pendSusp', estado: 'pendiente', createdAt: serverTimestamp() }));
  await assertFails(deleteDoc(lote(db, 'pendBorrador')));
});

test('3. un valor de cuentaEstado desconocido se trata como bloqueado (no como activo)', async () => {
  const db = dbDe('raro');
  await assertFails(updateDoc(lote(db, 'raroLote'), ediciones()));
  await assertFails(setDoc(doc(db, 'coffeeLots', 'nuevoCafe'), loteNuevo('raro')));
  await assertFails(updateDoc(doc(db, 'sellerProfiles', 'raro'), { nombreMarca: 'Otra', updatedAt: serverTimestamp() }));
});

test('3. un café suspendido tampoco se edita aunque la cuenta del dueño esté activa', async () => {
  const db = dbDe('sel');
  await assertFails(updateDoc(lote(db, 'selSusp'), ediciones()));
  await assertFails(updateDoc(lote(db, 'selSusp'), { estado: 'publicado', updatedAt: serverTimestamp() }));
});

test('3. nadie desde la app puede escribir estadoPrevio ni suspensionSolicitudId, ni suspender un café', async () => {
  const db = dbDe('sel');
  await assertFails(updateDoc(lote(db, 'loteSel'), { estadoPrevio: 'publicado', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(lote(db, 'loteSel'), { suspensionSolicitudId: 'x', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(lote(db, 'loteSel'), { estado: 'suspendido', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'coffeeLots', 'nuevoSusp'), { ...loteNuevo('sel'), estado: 'suspendido' }));
});

test('3. comprador pendiente NO puede enviar solicitudes de contacto, mensajes ni cotizaciones', async () => {
  const db = dbDe('cpend');
  await assertFails(setDoc(solicitud(db, 'cpend_loteSel'), solicitudNueva('cpend', 'sel', 'loteSel')));
  await assertFails(setDoc(doc(db, 'chats', 'ok_cpend', 'messages', 'nuevo'), { senderId: 'cpend', texto: 'Hola', createdAt: serverTimestamp() }));
  await assertFails(setDoc(cotizacion(db, 'qNueva'), cotizacionNueva('ok_cpend', 'cpend', 'ana', 'loteAna')));
  // control equivalente con un comprador activo
  await assertSucceeds(setDoc(solicitud(dbDe('comp3'), 'comp3_loteSel'), solicitudNueva('comp3', 'sel', 'loteSel')));
});

test('3. vendedor pendiente NO puede responder solicitudes ni cotizaciones ni escribir en el chat', async () => {
  const db = dbDe('pend');
  await assertFails(updateDoc(solicitud(db, 'pend_dePend'), { estado: 'aceptada', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(solicitud(db, 'pend_dePend'), { estado: 'rechazada', updatedAt: serverTimestamp() }));
  const lote1 = writeBatch(db);
  lote1.update(cotizacion(db, 'qPend'), { estado: 'solicitudRechazada', updatedAt: serverTimestamp() });
  lote1.set(doc(db, 'quotes', 'qPend', 'events', 'e1'), { tipo: 'solicitudRechazada', actor: 'vendedor', actorId: 'pend', fecha: serverTimestamp() });
  await assertFails(lote1.commit());
  await assertFails(setDoc(doc(db, 'chats', 'ok_pend', 'messages', 'nuevo'), { senderId: 'pend', texto: 'Hola', createdAt: serverTimestamp() }));
  const msg = writeBatch(db);
  msg.set(doc(db, 'chats', 'ok_pend', 'messages', 'm9'), { senderId: 'pend', texto: 'Hola', createdAt: serverTimestamp() });
  msg.update(solicitud(db, 'ok_pend'), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'pend', ultimoMensajeId: 'm9' });
  await assertFails(msg.commit());
});

// ---- 4. La contraparte de una cuenta pendiente tampoco puede avanzar la negociación ----

test('4. un vendedor activo NO puede aceptar la solicitud de un comprador pendiente', async () => {
  await assertFails(updateDoc(solicitud(dbDe('ana'), 'pend_deCpend'), { estado: 'aceptada', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(solicitud(dbDe('ana'), 'pend_ana'), { estado: 'aceptada', updatedAt: serverTimestamp() })); // control
});

test('4. un comprador activo NO puede volver a solicitar a un vendedor pendiente', async () => {
  const db = dbDe('comp');
  await assertFails(updateDoc(solicitud(db, 'rech_pend'), { estado: 'pendiente', mensaje: null, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(solicitud(db, 'rech_ana'), { estado: 'pendiente', mensaje: null, updatedAt: serverTimestamp() })); // control
});

test('4. un comprador activo NO puede crear solicitudes de contacto a un vendedor pendiente', async () => {
  await assertFails(setDoc(solicitud(dbDe('comp3'), 'comp3_pendPub'), solicitudNueva('comp3', 'pend', 'pendPub')));
});

test('4. el comprador activo NO puede escribir ni cotizar con el vendedor pendiente', async () => {
  const db = dbDe('comp');
  await assertFails(setDoc(doc(db, 'chats', 'ok_pend', 'messages', 'nuevo'), { senderId: 'comp', texto: 'Hola', createdAt: serverTimestamp() }));
  await assertFails(setDoc(cotizacion(db, 'qNueva'), cotizacionNueva('ok_pend', 'comp', 'pend', 'pendPub')));
  const msg = writeBatch(db);
  msg.set(doc(db, 'chats', 'ok_pend', 'messages', 'm9'), { senderId: 'comp', texto: 'Hola', createdAt: serverTimestamp() });
  msg.update(solicitud(db, 'ok_pend'), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'comp', ultimoMensajeId: 'm9' });
  await assertFails(msg.commit());
});

test('4. el comprador activo NO puede avanzar una cotización cuyo vendedor está pendiente', async () => {
  const db = dbDe('comp');
  const cancelar = writeBatch(db);
  cancelar.update(cotizacion(db, 'qPend'), { estado: 'cancelada', updatedAt: serverTimestamp() });
  cancelar.set(doc(db, 'quotes', 'qPend', 'events', 'e1'), { tipo: 'cancelada', actor: 'comprador', actorId: 'comp', fecha: serverTimestamp() });
  await assertFails(cancelar.commit());
  // control: la misma acción con un vendedor activo pasa
  const ok = writeBatch(db);
  ok.update(cotizacion(db, 'qAna'), { estado: 'cancelada', updatedAt: serverTimestamp() });
  ok.set(doc(db, 'quotes', 'qAna', 'events', 'e1'), { tipo: 'cancelada', actor: 'comprador', actorId: 'comp', fecha: serverTimestamp() });
  await assertSucceeds(ok.commit());
});

test('4. el vendedor activo NO puede cotizar a un comprador pendiente', async () => {
  const db = dbDe('ana');
  const lote1 = writeBatch(db);
  lote1.update(cotizacion(db, 'qCpend'), { estado: 'solicitudRechazada', updatedAt: serverTimestamp() });
  lote1.set(doc(db, 'quotes', 'qCpend', 'events', 'e1'), { tipo: 'solicitudRechazada', actor: 'vendedor', actorId: 'ana', fecha: serverTimestamp() });
  await assertFails(lote1.commit());
  await assertFails(setDoc(doc(db, 'chats', 'ok_cpend', 'messages', 'nuevo'), { senderId: 'ana', texto: 'Hola', createdAt: serverTimestamp() }));
});

// ---- 5. La cuenta pendiente conserva la lectura de su información e historial ----

test('5. la cuenta pendiente lee su usuario, su perfil, sus cafés (incluido el suspendido) y su historial', async () => {
  const db = dbDe('pend');
  await assertSucceeds(getDoc(doc(db, 'users', 'pend')));
  await assertSucceeds(getDoc(doc(db, 'sellerProfiles', 'pend')));
  await assertSucceeds(getDoc(lote(db, 'pendSusp')));
  await assertSucceeds(getDocs(query(collection(db, 'coffeeLots'), where('sellerId', '==', 'pend'))));
  await assertSucceeds(getDocs(query(collection(db, 'interestRequests'), where('sellerId', '==', 'pend'))));
  await assertSucceeds(getDocs(query(collection(db, 'quotes'), where('sellerId', '==', 'pend'))));
  await assertSucceeds(getDoc(doc(db, 'chats', 'ok_pend', 'messages', 'm0')));
  await assertSucceeds(getDoc(doc(db, 'quotes', 'qPend', 'events', 'e0')));
  await assertSucceeds(getDocs(collection(db, 'users', 'pend', 'pendingFileDeletions')));
});

test('5. la contraparte también sigue leyendo el historial compartido con la cuenta pendiente', async () => {
  const db = dbDe('comp');
  await assertSucceeds(getDoc(solicitud(db, 'ok_pend')));
  await assertSucceeds(getDoc(doc(db, 'chats', 'ok_pend', 'messages', 'm0')));
  await assertSucceeds(getDoc(cotizacion(db, 'qPend')));
});

test('5. la cuenta pendiente puede marcar un chat como leído (no avanza la negociación)', async () => {
  await assertSucceeds(updateDoc(solicitud(dbDe('pend'), 'ok_pend'), { leidoVendedor: serverTimestamp() }));
});

test('5. un café suspendido NO es legible por otras personas; un café publicado sí', async () => {
  const db = dbDe('comp');
  await assertFails(getDoc(lote(db, 'pendSusp')));
  await assertSucceeds(getDoc(lote(db, 'pendPub')));
  await assertSucceeds(getDocs(query(collection(db, 'coffeeLots'), where('estado', '==', 'publicado'))));
  await assertFails(getDocs(query(collection(db, 'coffeeLots'), where('estado', '==', 'suspendido'))));
});

// ---- 6. accountDeletionJobs: inaccesible para clientes ----

test('6. el cliente no puede crear, leer, actualizar ni borrar accountDeletionJobs (ni la dueña del trabajo)', async () => {
  for (const uid of ['pend', 'ana', 'comp']) {
    const db = dbDe(uid);
    const job = doc(db, 'accountDeletionJobs', uid);
    await assertFails(setDoc(job, { estado: 'pendiente', solicitudId: 'x', programadaAt: PROGRAMADA }));
    await assertFails(getDoc(doc(db, 'accountDeletionJobs', 'pend')));
    await assertFails(updateDoc(doc(db, 'accountDeletionJobs', 'pend'), { estado: 'cancelado' }));
    await assertFails(deleteDoc(doc(db, 'accountDeletionJobs', 'pend')));
    await assertFails(getDocs(collection(db, 'accountDeletionJobs')));
    await assertFails(getDoc(doc(db, 'accountDeletionJobs', 'pend', 'detalle', 'x')));
    await assertFails(setDoc(doc(db, 'accountDeletionJobs', uid, 'detalle', 'y'), { dato: 2 }));
  }
  // y el trabajo sigue intacto
  const job = await leerSinReglas('accountDeletionJobs/pend');
  if (job.estado !== 'pendiente') throw new Error('el trabajo cambió');
});

test('6. un usuario sin sesión tampoco accede a accountDeletionJobs', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'accountDeletionJobs', 'pend')));
  await assertFails(setDoc(doc(db, 'accountDeletionJobs', 'pend'), { estado: 'cancelado' }));
});

// ---- 7 y 8. Los campos de control de la cuenta no se escriben desde el cliente ----

test('7. el cliente no puede escribir cuentaEstado, eliminacionSolicitadaAt ni eliminacionProgramadaAt', async () => {
  const db = dbDe('ana');
  const ref = doc(db, 'users', 'ana');
  await assertFails(updateDoc(ref, { cuentaEstado: 'eliminacionPendiente', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { cuentaEstado: 'activa', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { eliminacionSolicitadaAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { eliminacionProgramadaAt: PROGRAMADA, updatedAt: serverTimestamp() }));
  // mezclados con un cambio legítimo tampoco pasan
  await assertFails(updateDoc(ref, { nombre: 'Ana B', cuentaEstado: 'eliminacionPendiente', updatedAt: serverTimestamp() }));
  // control: un cambio legítimo del perfil sí
  await assertSucceeds(updateDoc(ref, { nombre: 'Ana B', updatedAt: serverTimestamp() }));
});

test('7. al crear su documento, el cliente tampoco puede incluir esos campos', async () => {
  const db = dbDe('nuevo', { email: 'nuevo@x.co' });
  const base = { uid: 'nuevo', email: 'nuevo@x.co', rol: 'comprador', nombre: 'Nuevo', onboardingCompleto: false, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
  await assertFails(setDoc(doc(db, 'users', 'nuevo'), { ...base, cuentaEstado: 'activa' }));
  await assertFails(setDoc(doc(db, 'users', 'nuevo'), { ...base, eliminacionProgramadaAt: PROGRAMADA }));
  await assertSucceeds(setDoc(doc(db, 'users', 'nuevo'), base)); // control
});

test('8. una cuenta pendiente no puede volver a «activa» con una escritura directa', async () => {
  const db = dbDe('pend');
  const ref = doc(db, 'users', 'pend');
  await assertFails(updateDoc(ref, { cuentaEstado: 'activa', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { cuentaEstado: deleteField(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { cuentaEstado: 'activa', eliminacionSolicitadaAt: null, eliminacionProgramadaAt: null, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { eliminacionProgramadaAt: deleteField(), updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref, { uid: 'pend', email: 'pend@x.co', rol: 'vendedor', nombre: 'Pend', cuentaEstado: 'activa', updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(ref));
  const u = await leerSinReglas('users/pend');
  if (u.cuentaEstado !== 'eliminacionPendiente') throw new Error('la cuenta dejó de estar pendiente');
});
