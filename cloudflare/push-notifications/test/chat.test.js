// Mensajes de chat: verificación del mensaje, la conexión y el cálculo del destinatario.
import test from 'node:test';
import assert from 'node:assert/strict';
import { AJENO, COMPRADOR, VENDEDOR, mundoDeChat } from './_helpers.js';
import { CHAT, pedir } from './_pedir.js';

test('mensaje del comprador → se avisa SOLO al vendedor, con texto genérico', async () => {
  const w = await mundoDeChat();
  w.ponerDispositivo(COMPRADOR, 'devC', w.tokenValido('tokC')); // el autor también tiene dispositivo
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.estado, 'enviado');
  assert.equal(w.enviados.length, 1);
  const { token, cuerpo } = w.enviados[0];
  assert.equal(token, w.tokenValido('tokV1')); // dispositivo del vendedor
  assert.deepEqual(cuerpo.message.data, { ruta: 'chat', id: 'uid_comprador_lot1' });
  assert.equal(cuerpo.message.notification.body, 'Tienes un nuevo mensaje en Lotea Café');
  assert.equal(cuerpo.message.android.notification.channel_id, 'lotea_mensajes_cotizaciones');
});

test('el contenido privado del chat NUNCA viaja en la notificación', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  assert.equal(JSON.stringify(w.enviados[0].cuerpo).includes('SECRETO-DEL-CHAT'), false);
});

test('mensaje del vendedor → se avisa al comprador, no al propio vendedor', async () => {
  const w = await mundoDeChat();
  w.ponerConexion({ ultimoMensajeId: 'm2', ultimoMensajeDe: VENDEDOR });
  w.ponerMensaje('m2', { senderId: VENDEDOR });
  w.ponerDispositivo(COMPRADOR, 'devC', w.tokenValido('tokC'));
  const r = await pedir(w, { uid: VENDEDOR, cuerpo: CHAT('m2') });
  assert.equal(r.status, 200);
  assert.equal(w.enviados.length, 1);
  assert.equal(w.enviados[0].token, w.tokenValido('tokC'));
});

test('el remitente jamás recibe su propio aviso (solo tiene dispositivos él)', async () => {
  const w = await mundoDeChat();
  w.docs.delete(`users/${VENDEDOR}/deviceTokens/dev1`);
  w.ponerDispositivo(COMPRADOR, 'devC', w.tokenValido('tokC'));
  const r = await pedir(w);
  assert.equal(r.cuerpo.estado, 'sinDispositivos');
  assert.equal(w.enviados.length, 0);
});

test('mensaje inexistente → 404', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w, { cuerpo: CHAT('no-existe') });
  assert.equal(r.status, 404);
  assert.equal(w.enviados.length, 0);
});

test('conexión inexistente → 404', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedir(w, { cuerpo: CHAT('m1', 'uid_comprador_otro') })).status, 404);
});

test('remitente falsificado: el mensaje pertenece a OTRA persona → 403', async () => {
  const w = await mundoDeChat();
  w.ponerMensaje('m1', { senderId: VENDEDOR }); // el comprador reclama un mensaje del vendedor
  const r = await pedir(w);
  assert.equal(r.status, 403);
  assert.equal(w.enviados.length, 0);
});

test('conexión NO aceptada (pendiente o rechazada) → 409', async () => {
  for (const estado of ['pendiente', 'rechazada']) {
    const w = await mundoDeChat();
    w.ponerConexion({ estado });
    const r = await pedir(w);
    assert.equal(r.status, 409, estado);
    assert.equal(w.enviados.length, 0);
  }
});

test('persona ajena a la conexión → 403', async () => {
  const w = await mundoDeChat();
  const r = await pedir(w, { uid: AJENO });
  assert.equal(r.status, 403);
  assert.equal(w.enviados.length, 0);
});

test('el mensaje no es el último de la conexión (ultimoMensajeId distinto) → 409', async () => {
  const w = await mundoDeChat();
  w.ponerConexion({ ultimoMensajeId: 'm9', ultimoMensajeDe: COMPRADOR });
  w.ponerMensaje('m9');
  assert.equal((await pedir(w, { cuerpo: CHAT('m1') })).status, 409);
  assert.equal(w.enviados.length, 0);
});

test('ultimoMensajeDe no coincide con quien pide el aviso → 409', async () => {
  const w = await mundoDeChat();
  w.ponerConexion({ ultimoMensajeId: 'm1', ultimoMensajeDe: VENDEDOR });
  assert.equal((await pedir(w)).status, 409);
});

test('conexión sin ultimoMensajeId → 409', async () => {
  const w = await mundoDeChat();
  w.ponerConexion({ ultimoMensajeId: null });
  assert.equal((await pedir(w)).status, 409);
});

test('mensaje antiguo (fuera de la ventana de 15 min) → 409', async () => {
  const w = await mundoDeChat();
  w.ponerMensaje('m1', { edadMs: 16 * 60 * 1000 });
  assert.equal((await pedir(w)).status, 409);
});

test('mensaje sin fecha comprobable → 409', async () => {
  const w = await mundoDeChat();
  w.poner(`chats/uid_comprador_lot1/messages/m1`, { senderId: { stringValue: COMPRADOR } });
  assert.equal((await pedir(w)).status, 409);
});

test('las lecturas del chat se hacen con el token del usuario y nunca se escribe con él', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  const delUsuario = w.accesos.filter((a) => a.quien === 'usuario');
  assert.ok(delUsuario.length >= 2);
  assert.ok(delUsuario.every((a) => a.metodo === 'GET' && !a.ruta.includes('deviceTokens') && !a.ruta.startsWith('pushDedupe')));
});
