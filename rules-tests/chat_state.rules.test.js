// Pruebas REALES de firestore.rules contra el emulador de Firestore.
// Ejecutar desde esta carpeta (necesita Java y firebase-tools):
//   npm install && npm test
// Verifican el estado del chat en interestRequests: el «último mensaje» solo
// puede escribirse creando de verdad el mensaje en el mismo lote, y cada
// participante solo puede tocar su propia marca de lectura.
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, writeBatch, serverTimestamp, getDoc } from 'firebase/firestore';

const CONEXION = 'buyer1_lot1';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    // projectId PROPIO de este archivo (ver device_tokens.rules.test.js): evita que el
    // clearFirestore() de otro archivo en paralelo borre la conexión sembrada aquí.
    projectId: 'lotea-cafe-test-chat-state',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/buyer1'), { rol: 'comprador' });
    await setDoc(doc(db, 'users/seller1'), { rol: 'vendedor' });
    await setDoc(doc(db, 'interestRequests', CONEXION), {
      compradorId: 'buyer1', sellerId: 'seller1', coffeeLotId: 'lot1', estado: 'aceptada',
    });
  });
});

const dbDe = (uid) => env.authenticatedContext(uid).firestore();
const conexion = (db) => doc(db, 'interestRequests', CONEXION);
const mensaje = (db, id) => doc(db, 'chats', CONEXION, 'messages', id);

test('envío legítimo: mensaje + último mensaje en el mismo lote', async () => {
  const db = dbDe('buyer1');
  const lote = writeBatch(db);
  lote.set(mensaje(db, 'm1'), { senderId: 'buyer1', texto: 'Hola', createdAt: serverTimestamp() });
  lote.update(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'buyer1', ultimoMensajeId: 'm1' });
  await assertSucceeds(lote.commit());
});

test('el vendedor también puede enviar', async () => {
  const db = dbDe('seller1');
  const lote = writeBatch(db);
  lote.set(mensaje(db, 'm1'), { senderId: 'seller1', texto: 'Buenas', createdAt: serverTimestamp() });
  lote.update(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'seller1', ultimoMensajeId: 'm1' });
  await assertSucceeds(lote.commit());
});

test('actualizar el último mensaje SIN crear el mensaje se rechaza', async () => {
  const db = dbDe('buyer1');
  await assertFails(updateDoc(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'buyer1', ultimoMensajeId: 'fantasma' }));
});

test('apuntar a un mensaje que ya existía se rechaza (no se reutiliza)', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'chats', CONEXION, 'messages', 'viejo'), { senderId: 'buyer1', texto: 'x', createdAt: new Date() });
  });
  const db = dbDe('buyer1');
  await assertFails(updateDoc(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'buyer1', ultimoMensajeId: 'viejo' }));
});

test('no se puede declarar como remitente a la otra persona', async () => {
  const db = dbDe('buyer1');
  const lote = writeBatch(db);
  lote.set(mensaje(db, 'm1'), { senderId: 'buyer1', texto: 'Hola', createdAt: serverTimestamp() });
  lote.update(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'seller1', ultimoMensajeId: 'm1' });
  await assertFails(lote.commit());
});

test('el mensaje del lote debe ser del remitente autenticado (la regla de mensajes lo exige)', async () => {
  const db = dbDe('buyer1');
  const lote = writeBatch(db);
  lote.set(mensaje(db, 'm1'), { senderId: 'seller1', texto: 'suplantado', createdAt: serverTimestamp() });
  lote.update(conexion(db), { ultimoMensajeAt: serverTimestamp(), ultimoMensajeDe: 'buyer1', ultimoMensajeId: 'm1' });
  await assertFails(lote.commit());
});

test('una hora distinta de la del servidor se rechaza', async () => {
  const db = dbDe('buyer1');
  const lote = writeBatch(db);
  lote.set(mensaje(db, 'm1'), { senderId: 'buyer1', texto: 'Hola', createdAt: serverTimestamp() });
  lote.update(conexion(db), { ultimoMensajeAt: new Date('2020-01-01'), ultimoMensajeDe: 'buyer1', ultimoMensajeId: 'm1' });
  await assertFails(lote.commit());
});

test('un ajeno no puede tocar la conexión', async () => {
  const db = dbDe('intruso');
  await assertFails(updateDoc(conexion(db), { leidoComprador: serverTimestamp() }));
  await assertFails(getDoc(conexion(db)));
});

test('cada participante marca SOLO su propia lectura', async () => {
  await assertSucceeds(updateDoc(conexion(dbDe('buyer1')), { leidoComprador: serverTimestamp() }));
  await assertSucceeds(updateDoc(conexion(dbDe('seller1')), { leidoVendedor: serverTimestamp() }));
});

test('nadie puede cambiar la marca de lectura de la otra persona', async () => {
  await assertFails(updateDoc(conexion(dbDe('buyer1')), { leidoVendedor: serverTimestamp() }));
  await assertFails(updateDoc(conexion(dbDe('seller1')), { leidoComprador: serverTimestamp() }));
});

test('la marca de lectura debe llevar la hora del servidor', async () => {
  await assertFails(updateDoc(conexion(dbDe('buyer1')), { leidoComprador: new Date('2020-01-01') }));
});

test('no se mezclan campos de lectura con otros campos', async () => {
  await assertFails(updateDoc(conexion(dbDe('buyer1')), { leidoComprador: serverTimestamp(), estado: 'rechazada' }));
});

test('una conexión no aceptada no admite estado de chat', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'interestRequests', CONEXION), { estado: 'pendiente' });
  });
  await assertFails(updateDoc(conexion(dbDe('buyer1')), { leidoComprador: serverTimestamp() }));
});
