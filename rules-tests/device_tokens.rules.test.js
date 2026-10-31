// Pruebas de las reglas de users/{uid}/deviceTokens y pushDedupe contra el EMULADOR
// de Firestore. Ejecutar desde esta carpeta (necesita Java y firebase-tools):
//   npm install && npm test
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

let env;
const TOKEN = 'fcm_token_de_prueba_con_mas_de_veinte_caracteres';

before(async () => {
  env = await initializeTestEnvironment({
    // projectId PROPIO de este archivo: `node --test a b` ejecuta los archivos en
    // paralelo contra el mismo emulador, y clearFirestore() borra todo el proyecto.
    projectId: 'lotea-cafe-test-device-tokens',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    // UN solo cliente por contexto: llamar a ctx.firestore() otra vez sobre el mismo
    // contexto reaplica la configuración del emulador a un Firestore ya iniciado y
    // lanza «Firestore has already been started and its settings can no longer be changed».
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/ana/deviceTokens/existente'), { token: TOKEN, plataforma: 'android', updatedAt: new Date() });
    await setDoc(doc(db, 'pushDedupe/abc'), { estado: 'enviado' });
  });
});

const dbDe = (uid) => env.authenticatedContext(uid).firestore();
const tokenDoc = (db, uid, id) => doc(db, 'users', uid, 'deviceTokens', id);
const valido = () => ({ token: TOKEN, plataforma: 'android', updatedAt: serverTimestamp() });

test('cada persona puede registrar su propio dispositivo', async () => {
  await assertSucceeds(setDoc(tokenDoc(dbDe('ana'), 'ana', 'dev1'), valido()));
});
test('puede actualizar (renovar) y borrar su dispositivo, y leer los suyos', async () => {
  const db = dbDe('ana');
  await assertSucceeds(setDoc(tokenDoc(db, 'ana', 'existente'), valido()));
  await assertSucceeds(getDoc(tokenDoc(db, 'ana', 'existente')));
  await assertSucceeds(deleteDoc(tokenDoc(db, 'ana', 'existente')));
});
test('no puede escribir, leer ni borrar los tokens de OTRA persona', async () => {
  const db = dbDe('beto');
  await assertFails(setDoc(tokenDoc(db, 'ana', 'dev2'), valido()));
  await assertFails(getDoc(tokenDoc(db, 'ana', 'existente')));
  await assertFails(deleteDoc(tokenDoc(db, 'ana', 'existente')));
  await assertFails(updateDoc(tokenDoc(db, 'ana', 'existente'), { token: TOKEN + 'x', updatedAt: serverTimestamp() }));
});
test('sin sesión no se puede nada', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(tokenDoc(db, 'ana', 'dev1'), valido()));
  await assertFails(getDoc(tokenDoc(db, 'ana', 'existente')));
});
test('se rechazan campos extra, campos que faltan, plataforma inválida y token demasiado corto o largo', async () => {
  const db = dbDe('ana');
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x1'), { ...valido(), extra: 1 }));
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x2'), { token: TOKEN, plataforma: 'android' }));
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x3'), { ...valido(), plataforma: 'windows' }));
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x4'), { ...valido(), token: 'corto' }));
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x5'), { ...valido(), token: 'x'.repeat(4097) }));
  await assertFails(setDoc(tokenDoc(db, 'ana', 'x6'), { ...valido(), token: 12345678901234567890 }));
});
test('updatedAt debe ser la hora del servidor, no una fecha del cliente', async () => {
  await assertFails(setDoc(tokenDoc(dbDe('ana'), 'ana', 'x7'), { ...valido(), updatedAt: new Date('2020-01-01') }));
});
test('pushDedupe (uso interno del Worker) no se puede leer ni escribir desde el cliente', async () => {
  const db = dbDe('ana');
  await assertFails(getDoc(doc(db, 'pushDedupe/abc')));
  await assertFails(setDoc(doc(db, 'pushDedupe/nuevo'), { estado: 'enviado' }));
  await assertFails(deleteDoc(doc(db, 'pushDedupe/abc')));
});
test('registrar un dispositivo no abre el resto del perfil: users/{otro} sigue sin ser legible', async () => {
  await assertFails(getDoc(doc(dbDe('beto'), 'users/ana')));
});
