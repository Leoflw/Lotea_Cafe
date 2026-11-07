// Solicitud mal formada, tipos de evento no permitidos e intento de dictar el destinatario.
import test from 'node:test';
import assert from 'node:assert/strict';
import { VENDEDOR, mundoDeChat } from './_helpers.js';
import { CHAT, COT, pedir } from './_pedir.js';

test('JSON inválido, array y valores no objeto → 400', async () => {
  const w = await mundoDeChat();
  for (const cuerpo of ['{no es json', '[]', '"texto"', 'null', '42']) {
    assert.equal((await pedir(w, { cuerpo })).status, 400, cuerpo);
  }
  assert.equal(w.enviados.length, 0);
});

test('tipo de evento ausente, desconocido o heredado de Object → 400', async () => {
  const w = await mundoDeChat();
  for (const tipo of [undefined, 'otroTipo', 'solicitudCreada', '__proto__', 'constructor', 7, null]) {
    const r = await pedir(w, { cuerpo: { tipo, connectionId: 'a', messageId: 'b' } });
    assert.equal(r.status, 400, String(tipo));
  }
});

test('faltan identificadores o tienen caracteres no permitidos → 400', async () => {
  const w = await mundoDeChat();
  const malos = [
    { tipo: 'chatMessage', connectionId: 'uid_comprador_lot1' },
    { tipo: 'chatMessage', messageId: 'm1' },
    { tipo: 'chatMessage', connectionId: '../users/otro', messageId: 'm1' },
    { tipo: 'chatMessage', connectionId: 'a/b', messageId: 'm1' },
    { tipo: 'chatMessage', connectionId: 'a', messageId: '' },
    { tipo: 'chatMessage', connectionId: 'a', messageId: 'x'.repeat(301) },
    { tipo: 'chatMessage', connectionId: 5, messageId: 'm1' },
    { tipo: 'quoteEvent', quoteId: 'q1' },
    { tipo: 'quoteEvent', quoteId: 'q1', eventId: 'e 1' },
    { tipo: 'quoteEvent', quoteId: 'q?1', eventId: 'e1' },
    { tipo: 'quoteEvent', connectionId: 'a', messageId: 'b' }, // campos del otro tipo
  ];
  for (const cuerpo of malos) assert.equal((await pedir(w, { cuerpo })).status, 400, JSON.stringify(cuerpo));
});

test('el cliente NO puede indicar destinatario, token FCM, texto ni ruta: 400 y no se envía nada', async () => {
  const w = await mundoDeChat();
  const intentos = [
    { destinatarioUid: VENDEDOR },
    { recipientUid: 'uid_victima' },
    { uid: 'uid_victima' },
    { to: 'uid_victima' },
    { fcmToken: 'token_de_otro_dispositivo_xxxxxxxxxxxx' },
    { token: 'token_de_otro_dispositivo_xxxxxxxxxxxx' },
    { title: 'Gana un premio', body: 'Haz clic aquí' },
    { notification: { title: 'x', body: 'y' } },
    { path: '/users/otro/deviceTokens' },
    { ruta: 'chat', id: 'otra' },
    { data: { ruta: 'chat' } },
  ];
  for (const extra of intentos) {
    const r = await pedir(w, { cuerpo: { ...CHAT(), ...extra } });
    assert.equal(r.status, 400, JSON.stringify(extra));
  }
  for (const extra of intentos) {
    const r = await pedir(w, { cuerpo: { ...COT(), ...extra } });
    assert.equal(r.status, 400, JSON.stringify(extra));
  }
  assert.equal(w.enviados.length, 0);
  // Ni siquiera se consultó Firestore: la validación ocurre antes.
  assert.equal(w.accesos.length, 0);
});

test('cuerpo demasiado grande → 413', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w, { cuerpo: JSON.stringify({ ...CHAT(), relleno: 'x'.repeat(2000) }) });
  assert.equal(r.status, 413);
});

test('limitador de mejor esfuerzo: tras 60 avisos seguidos de un usuario → 429', async () => {
  const w = await mundoDeChat();
  let ultimo;
  for (let i = 0; i < 61; i++) ultimo = await pedir(w, { cuerpo: CHAT(`m${i}`) });
  assert.equal(ultimo.status, 429);
});
