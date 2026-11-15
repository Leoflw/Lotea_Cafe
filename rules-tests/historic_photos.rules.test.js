// Pruebas de integridad del HISTORIAL de negociaciones (interestRequests.loteFoto y quotes.loteFoto)
// y de las solicitudes de eliminación de lote, contra el EMULADOR de Firestore. Ejecutar desde esta
// carpeta (necesita Java y firebase-tools): npm install && npm test
//
// Lo que demuestran: NADIE desde la app puede cambiar `loteFoto` (ni participantes ni terceros);
// solo el Worker de limpieza, con cuenta de servicio (que no pasa por estas reglas), lo deja en null.
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { loteReal } from './fixtures.js';

let env;
const FOTO = 'https://ik.imagekit.io/demo/lotea-cafe/users/ana/lots/a.jpg';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'lotea-cafe-test-historic-photos',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/ana'), { rol: 'vendedor', nombre: 'Ana' });
    await setDoc(doc(db, 'users/beto'), { rol: 'vendedor', nombre: 'Beto' });
    await setDoc(doc(db, 'users/carla'), { rol: 'comprador', nombre: 'Carla' });
    await setDoc(doc(db, 'users/dario'), { rol: 'comprador', nombre: 'Dario' });
    await setDoc(doc(db, 'coffeeLots/lote1'), loteReal({ nombre: 'A', fotos: [FOTO] }));
    await setDoc(doc(db, 'interestRequests/carla_lote1'), {
      compradorId: 'carla', sellerId: 'ana', coffeeLotId: 'lote1', estado: 'pendiente', loteFoto: FOTO, loteNombre: 'A',
      createdAt: new Date(), updatedAt: new Date(),
    });
    await setDoc(doc(db, 'quotes/q1'), {
      compradorId: 'carla', sellerId: 'ana', coffeeLotId: 'lote1', estado: 'solicitudPendiente', loteFoto: FOTO,
      oferta: null, createdAt: new Date(), updatedAt: new Date(),
    });
  });
});

const dbDe = (uid) => env.authenticatedContext(uid).firestore();
const sol = (db) => doc(db, 'interestRequests/carla_lote1');
const cot = (db) => doc(db, 'quotes/q1');

test('el comprador NO puede cambiar loteFoto de su solicitud ni de su cotización', async () => {
  const db = dbDe('carla');
  await assertFails(updateDoc(sol(db), { loteFoto: null, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(cot(db), { loteFoto: null, updatedAt: serverTimestamp() }));
});
test('el vendedor NO puede cambiar loteFoto, ni siquiera junto con una transición válida', async () => {
  const db = dbDe('ana');
  await assertFails(updateDoc(sol(db), { loteFoto: null, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(sol(db), { estado: 'aceptada', loteFoto: null, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(cot(db), { estado: 'solicitudRechazada', loteFoto: null, updatedAt: serverTimestamp() }));
  // Controles positivos: las transiciones normales siguen funcionando sin tocar loteFoto.
  await assertSucceeds(updateDoc(sol(db), { estado: 'aceptada', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(cot(db), { estado: 'solicitudRechazada', updatedAt: serverTimestamp() }));
});
test('una persona AJENA a la negociación no puede leer ni modificar sus fotos históricas', async () => {
  for (const uid of ['beto', 'dario']) {
    const db = dbDe(uid);
    await assertFails(getDoc(sol(db)));
    await assertFails(getDoc(cot(db)));
    await assertFails(updateDoc(sol(db), { loteFoto: null, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(cot(db), { loteFoto: null, updatedAt: serverTimestamp() }));
  }
});
test('nadie puede borrar solicitudes ni cotizaciones (el historial no se elimina desde la app)', async () => {
  await assertFails(deleteDoc(sol(dbDe('ana'))));
  await assertFails(deleteDoc(sol(dbDe('carla'))));
  await assertFails(deleteDoc(cot(dbDe('ana'))));
});

// ---- Solicitudes de eliminación de lote: users/{uid}/pendingLotDeletions/{lotId} ----
const lote = (db, uid, id) => doc(db, 'users', uid, 'pendingLotDeletions', id);
const pedido = (extra = {}) => ({ lotId: 'lote1', estado: 'pendiente', createdAt: serverTimestamp(), ...extra });

test('el vendedor puede pedir la eliminación de SU lote', async () => {
  await assertSucceeds(setDoc(lote(dbDe('ana'), 'ana', 'lote1'), pedido()));
});
test('no puede pedir la eliminación del lote de otra persona (ni en su cola ni en la ajena)', async () => {
  await assertFails(setDoc(lote(dbDe('beto'), 'beto', 'lote1'), pedido())); // lote de ana, cola de beto
  await assertFails(setDoc(lote(dbDe('beto'), 'ana', 'lote1'), pedido())); // cola de ana
});
test('no puede pedir la eliminación de un lote que no existe', async () => {
  await assertFails(setDoc(lote(dbDe('ana'), 'ana', 'inexistente'), pedido({ lotId: 'inexistente' })));
});
test('el estado inicial es «pendiente», sin campos del Worker, con id válido y fecha del servidor', async () => {
  const db = dbDe('ana');
  await assertFails(setDoc(lote(db, 'ana', 'lote1'), pedido({ estado: 'completado' })));
  await assertFails(setDoc(lote(db, 'ana', 'lote1'), pedido({ intentos: 0 })));
  await assertFails(setDoc(lote(db, 'ana', 'lote1'), pedido({ lotId: 'otro' })));
  await assertFails(setDoc(lote(db, 'ana', 'lote1'), pedido({ createdAt: new Date('2000-01-01T00:00:00.000Z') })));
});
test('no se puede cambiar ni borrar la solicitud (salvo reabrir una «fallido»); solo su dueño la lee', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/ana/pendingLotDeletions/lote1'), { lotId: 'lote1', estado: 'procesando' });
  });
  const db = dbDe('ana');
  await assertFails(updateDoc(lote(db, 'ana', 'lote1'), { estado: 'completado' }));
  await assertFails(deleteDoc(lote(db, 'ana', 'lote1')));
  await assertFails(updateDoc(lote(db, 'ana', 'lote1'), { estado: 'pendiente', createdAt: serverTimestamp() })); // no está «fallido»
  await assertFails(getDoc(lote(dbDe('beto'), 'ana', 'lote1')));
  await assertSucceeds(getDoc(lote(db, 'ana', 'lote1')));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/ana/pendingLotDeletions/lote1'), { lotId: 'lote1', estado: 'fallido' });
  });
  await assertSucceeds(updateDoc(lote(db, 'ana', 'lote1'), { estado: 'pendiente', createdAt: serverTimestamp() }));
});
