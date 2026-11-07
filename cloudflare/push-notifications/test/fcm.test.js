// Dispositivos del destinatario, tokens inválidos y errores de Google.
import test from 'node:test';
import assert from 'node:assert/strict';
import { clasificarError } from '../src/fcm.js';
import { FCM, VENDEDOR, mundoDeChat } from './_helpers.js';
import { pedir } from './_pedir.js';

test('destinatario SIN ningún token → 200 «sinDispositivos» y FCM no se llama', async () => {
  const w = await mundoDeChat();
  w.docs.delete(`users/${VENDEDOR}/deviceTokens/dev1`);
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.estado, 'sinDispositivos');
  assert.equal(w.enviados.length, 0);
});

test('varios dispositivos: se envía a cada uno (el más reciente primero)', async () => {
  const w = await mundoDeChat();
  w.ponerDispositivo(VENDEDOR, 'dev2', w.tokenValido('tokV2'), 50);
  const r = await pedir(w);
  assert.equal(r.cuerpo.enviados, 2);
  assert.deepEqual(w.enviados.map((e) => e.token).sort(), [w.tokenValido('tokV1'), w.tokenValido('tokV2')].sort());
});

test('se ignoran registros sin token o con token de longitud imposible', async () => {
  const w = await mundoDeChat();
  w.poner(`users/${VENDEDOR}/deviceTokens/vacio`, { plataforma: { stringValue: 'android' } });
  w.poner(`users/${VENDEDOR}/deviceTokens/corto`, { token: { stringValue: 'abc' } });
  const r = await pedir(w);
  assert.equal(r.cuerpo.enviados, 1);
});

test('token inexistente (UNREGISTERED): se ELIMINA del registro de su dueño y el otro dispositivo sí recibe', async () => {
  const w = await mundoDeChat();
  w.ponerDispositivo(VENDEDOR, 'devMuerto', w.tokenValido('muerto'), 9000);
  w.respuestasFcm.set(w.tokenValido('muerto'), FCM.noRegistrado);
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.enviados, 1);
  assert.equal(r.cuerpo.tokensEliminados, 1);
  assert.deepEqual(w.dispositivos(VENDEDOR), [`users/${VENDEDOR}/deviceTokens/dev1`]);
});

test('token mal formado (INVALID_ARGUMENT sobre message.token) → se elimina', async () => {
  const w = await mundoDeChat();
  w.respuestasFcm.set(w.tokenValido('tokV1'), FCM.tokenMalFormado);
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.tokensEliminados, 1);
  assert.equal(w.dispositivos(VENDEDOR).length, 0);
});

test('solo se borra el token inválido de SU propietario: los de otras cuentas quedan intactos', async () => {
  const w = await mundoDeChat();
  w.ponerDispositivo(COMPRADOR_AJENO, 'devX', w.tokenValido('tokX'));
  w.respuestasFcm.set(w.tokenValido('tokV1'), FCM.noRegistrado);
  await pedir(w);
  assert.equal(w.dispositivos(COMPRADOR_AJENO).length, 1);
});
const COMPRADOR_AJENO = 'uid_otro';

test('si el token cambió mientras se enviaba (updateTime distinto) NO se borra el registro nuevo', async () => {
  const w = await mundoDeChat();
  w.respuestasFcm.set(w.tokenValido('tokV1'), () => {
    w.ponerDispositivo(VENDEDOR, 'dev1', w.tokenValido('tokV1'), 0); // el dispositivo se re-registró
    return FCM.noRegistrado();
  });
  const r = await pedir(w);
  assert.equal(r.cuerpo.tokensEliminados, 0);
  assert.equal(w.dispositivos(VENDEDOR).length, 1);
});

for (const [nombre, respuesta, esperado] of [
  ['503 UNAVAILABLE', FCM.noDisponible, 503],
  ['429 cuota', FCM.cuota, 503],
  ['500 INTERNAL', FCM.interno, 503],
  ['error de red', () => new Error('red caída'), 503],
]) {
  test(`error TEMPORAL (${nombre}): se responde ${esperado} y NO se borra el token`, async () => {
    const w = await mundoDeChat();
    w.respuestasFcm.set(w.tokenValido('tokV1'), respuesta);
    const r = await pedir(w);
    assert.equal(r.status, esperado);
    assert.equal(w.dispositivos(VENDEDOR).length, 1);
    assert.equal(w.dedupe().length, 0);
  });
}

for (const [nombre, respuesta] of [
  ['403 PERMISSION_DENIED', FCM.sinPermiso],
  ['SENDER_ID_MISMATCH', FCM.remitenteDistinto],
  ['404 genérico sin UNREGISTERED (p. ej. proyecto mal escrito)', FCM.noEncontradoGenerico],
  ['INVALID_ARGUMENT en otro campo (carga inválida)', FCM.cargaInvalida],
]) {
  test(`error de CONFIGURACIÓN (${nombre}): 502 y NO se borra ningún token`, async () => {
    const w = await mundoDeChat();
    w.respuestasFcm.set(w.tokenValido('tokV1'), respuesta);
    const r = await pedir(w);
    assert.equal(r.status, 502);
    assert.equal(w.dispositivos(VENDEDOR).length, 1);
    assert.equal(w.dedupe().length, 0, 'se libera para poder reintentar tras corregir la configuración');
  });
}

test('401 de Google: se renueva el access token UNA vez y el envío sale bien', async () => {
  const w = await mundoDeChat();
  w.rechazar401Una = true;
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.enviados, 1);
  assert.ok(w.llamadasOauth >= 2);
});

test('clasificarError: tabla de decisiones', () => {
  const cod = (errorCode, extra = {}) => ({ error: { details: [{ errorCode }], ...extra } });
  assert.equal(clasificarError(404, cod('UNREGISTERED')), 'tokenInvalido');
  assert.equal(clasificarError(404, { error: { status: 'NOT_FOUND' } }), 'configuracion');
  assert.equal(clasificarError(503, null), 'transitorio');
  assert.equal(clasificarError(500, {}), 'transitorio');
  assert.equal(clasificarError(429, cod('QUOTA_EXCEEDED')), 'transitorio');
  assert.equal(clasificarError(403, cod('SENDER_ID_MISMATCH')), 'configuracion');
  assert.equal(clasificarError(401, null), 'configuracion');
  assert.equal(clasificarError(400, null), 'configuracion');
});
