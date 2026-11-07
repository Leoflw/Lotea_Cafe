// Deduplicación persistente: un reintento HTTP no repite el aviso.
import test from 'node:test';
import assert from 'node:assert/strict';
import { LEASE_MS } from '../src/dedupe.js';
import { COMPRADOR, NOW_MS, VENDEDOR, mundoDeChat, mundoDeCotizacion, s } from './_helpers.js';
import { CHAT, COT, pedir } from './_pedir.js';
import { FCM } from './_helpers.js';

test('el segundo POST del mismo mensaje devuelve «duplicado» y FCM se llamó una sola vez', async () => {
  const w = await mundoDeChat();
  assert.equal((await pedir(w)).cuerpo.estado, 'enviado');
  const r2 = await pedir(w);
  assert.equal(r2.status, 200);
  assert.equal(r2.cuerpo.estado, 'duplicado');
  assert.equal(w.enviados.length, 1);
});

test('la deduplicación sobrevive al «reinicio» del Worker (vive en Firestore, no en memoria)', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  // Simula otra instancia: se vacía TODO el estado en memoria del Worker.
  const { resetJwksCache } = await import('../src/firebase.js');
  const { resetAuthCache } = await import('../src/google-auth.js');
  const { resetLimitador } = await import('../src/index.js');
  resetJwksCache(); resetAuthCache(); resetLimitador();
  assert.equal((await pedir(w)).cuerpo.estado, 'duplicado');
  assert.equal(w.enviados.length, 1);
});

test('dos peticiones simultáneas del mismo evento → un solo envío', async () => {
  const w = await mundoDeChat();
  const [a, b] = await Promise.all([pedir(w), pedir(w)]);
  assert.equal(w.enviados.length, 1);
  const estados = [a.cuerpo.estado, b.cuerpo.estado].sort();
  assert.ok(estados.includes('enviado'));
  assert.ok(estados.includes('duplicado') || estados.includes('enCurso'));
});

test('eventos distintos no se deduplican entre sí', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'solicitudCreada' });
  w.ponerEvento('e2', { tipo: 'cancelada' });
  await pedir(w, { cuerpo: COT('e1') });
  await pedir(w, { cuerpo: COT('e2') });
  assert.equal(w.enviados.length, 2);
  assert.equal(w.dedupe().length, 2);
});

test('el id del registro es un hash: no contiene identificadores ni tokens', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  const [[ruta, doc]] = w.dedupe();
  assert.match(ruta, /^pushDedupe\/[0-9a-f]{64}$/);
  assert.equal(doc.fields.estado.stringValue, 'enviado');
  assert.ok(doc.fields.expiraEn.timestampValue); // permite una política TTL opcional
  assert.equal(JSON.stringify(doc).includes('tokV1'), false);
});

test('error TEMPORAL de FCM en todos los dispositivos: 503, se LIBERA el registro y el reintento envía', async () => {
  const w = await mundoDeChat();
  w.respuestaFcmPorDefecto = FCM.noDisponible;
  const r1 = await pedir(w);
  assert.equal(r1.status, 503);
  assert.equal(r1.cuerpo.reintentable, true);
  assert.equal(w.dedupe().length, 0, 'el registro debe haberse liberado');

  w.respuestaFcmPorDefecto = FCM.ok;
  const r2 = await pedir(w);
  assert.equal(r2.status, 200);
  assert.equal(r2.cuerpo.estado, 'enviado');
  assert.equal(w.enviados.filter((e) => e.cuerpo).length, 2); // 1 intento fallido + 1 exitoso
});

test('envío PARCIAL (un dispositivo ok, otro con error temporal): queda «enviado» para no duplicar', async () => {
  const w = await mundoDeChat();
  w.ponerDispositivo(VENDEDOR, 'dev2', w.tokenValido('tokV2'), 5000);
  w.respuestasFcm.set(w.tokenValido('tokV2'), FCM.noDisponible);
  const r = await pedir(w);
  assert.equal(r.status, 200);
  assert.equal(r.cuerpo.enviados, 1);
  assert.equal(r.cuerpo.fallosTemporales, 1);
  assert.equal((await pedir(w)).cuerpo.estado, 'duplicado');
});

test('«enviando» reciente: otra petición está en curso → 202 y no se envía', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  const [[ruta, doc]] = w.dedupe();
  w.poner(ruta, { ...doc.fields, estado: s('enviando'), claimedAtMs: { integerValue: String(NOW_MS - 1000) } });
  const r = await pedir(w);
  assert.equal(r.status, 202);
  assert.equal(r.cuerpo.estado, 'enCurso');
  assert.equal(w.enviados.length, 1);
});

test('«enviando» abandonado (más de 60 s): se toma el relevo y se envía', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  const [[ruta, doc]] = w.dedupe();
  w.poner(ruta, { ...doc.fields, estado: s('enviando'), claimedAtMs: { integerValue: String(NOW_MS - LEASE_MS - 1000) } });
  const r = await pedir(w);
  assert.equal(r.cuerpo.estado, 'enviado');
  assert.equal(w.enviados.length, 2);
});

test('sin dispositivos NO se escribe ningún registro de deduplicación', async () => {
  const w = await mundoDeChat();
  w.docs.delete(`users/${VENDEDOR}/deviceTokens/dev1`);
  const r = await pedir(w);
  assert.equal(r.cuerpo.estado, 'sinDispositivos');
  assert.equal(w.dedupe().length, 0);
});

test('un usuario NO puede leer ni escribir pushDedupe con su token (el Worker nunca lo intenta)', async () => {
  const w = await mundoDeChat();
  await pedir(w);
  const conUsuario = w.accesos.filter((a) => a.quien === 'usuario');
  assert.ok(conUsuario.every((a) => !a.ruta.startsWith('pushDedupe') && !a.ruta.includes('deviceTokens')));
  assert.ok(w.accesos.filter((a) => a.ruta.startsWith('pushDedupe')).every((a) => a.quien === 'cuenta'));
  void COMPRADOR; void CHAT;
});
