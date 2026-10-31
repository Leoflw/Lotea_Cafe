// Eventos de cotización: tipos permitidos, autor, participación y destinatario.
import test from 'node:test';
import assert from 'node:assert/strict';
import { AJENO, COMPRADOR, VENDEDOR, mundoDeCotizacion } from './_helpers.js';
import { COT, pedir } from './_pedir.js';

// tipo → [quién lo ejecuta, a quién se avisa]
const TABLA = {
  solicitudCreada: [COMPRADOR, VENDEDOR],
  ofertaEnviada: [VENDEDOR, COMPRADOR],
  solicitudRechazada: [VENDEDOR, COMPRADOR],
  revisionSolicitada: [COMPRADOR, VENDEDOR],
  ofertaAceptada: [COMPRADOR, VENDEDOR],
  ofertaRechazada: [COMPRADOR, VENDEDOR],
  cancelada: [COMPRADOR, VENDEDOR],
};
const rolDe = (uid) => (uid === COMPRADOR ? 'comprador' : 'vendedor');

for (const [tipo, [autor, destino]] of Object.entries(TABLA)) {
  test(`${tipo}: lo ejecuta ${rolDe(autor)} y se avisa a ${rolDe(destino)} (nunca al autor)`, async () => {
    const w = await mundoDeCotizacion();
    w.ponerEvento('e1', { tipo, actor: rolDe(autor), actorId: autor });
    const r = await pedir(w, { uid: autor, cuerpo: COT() });
    assert.equal(r.status, 200);
    assert.equal(w.enviados.length, 1);
    const esperado = destino === VENDEDOR ? w.tokenValido('tokV') : w.tokenValido('tokC');
    assert.equal(w.enviados[0].token, esperado);
    assert.deepEqual(w.enviados[0].cuerpo.message.data, { ruta: 'cotizacion', id: 'q1' });
    assert.equal(w.enviados[0].cuerpo.message.notification.body, 'Tienes novedades en una cotización de Lotea Café');
  });
}

test('evento inexistente → 404', async () => {
  const w = await mundoDeCotizacion();
  assert.equal((await pedir(w, { cuerpo: COT('no-existe') })).status, 404);
  assert.equal(w.enviados.length, 0);
});

test('cotización inexistente → 404', async () => {
  const w = await mundoDeCotizacion();
  assert.equal((await pedir(w, { cuerpo: COT('e1', 'q-fantasma') })).status, 404);
});

test('evento ejecutado por OTRA persona (actorId distinto del usuario) → 403', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'ofertaEnviada', actor: 'vendedor', actorId: VENDEDOR });
  const r = await pedir(w, { uid: COMPRADOR, cuerpo: COT() }); // el comprador reclama el evento del vendedor
  assert.equal(r.status, 403);
  assert.equal(w.enviados.length, 0);
});

test('usuario que no participa en la cotización → 403', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'solicitudCreada', actor: 'comprador', actorId: AJENO });
  const r = await pedir(w, { uid: AJENO, cuerpo: COT() });
  assert.equal(r.status, 403);
  assert.equal(w.enviados.length, 0);
});

test('tipo de evento no permitido (inventado, vencimiento derivado o ausente) → 422', async () => {
  for (const tipo of ['ofertaVencida', 'inventado', '__proto__', '']) {
    const w = await mundoDeCotizacion();
    w.ponerEvento('e1', { tipo });
    const r = await pedir(w, { cuerpo: COT() });
    assert.equal(r.status, 422, tipo);
    assert.equal(w.enviados.length, 0);
  }
  const w = await mundoDeCotizacion();
  w.poner('quotes/q1/events/e1', { actorId: { stringValue: COMPRADOR } });
  assert.equal((await pedir(w, { cuerpo: COT() })).status, 422);
});

test('rol incongruente: el comprador no puede registrar «ofertaEnviada» aunque actorId sea suyo → 403', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'ofertaEnviada', actor: 'comprador', actorId: COMPRADOR });
  assert.equal((await pedir(w, { cuerpo: COT() })).status, 403);
  w.ponerEvento('e2', { tipo: 'ofertaEnviada', actor: 'vendedor', actorId: COMPRADOR }); // rol declarado falso
  assert.equal((await pedir(w, { cuerpo: COT('e2') })).status, 403);
  assert.equal(w.enviados.length, 0);
});

test('evento antiguo (fuera de la ventana de 15 min) → 409', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { edadMs: 20 * 60 * 1000 });
  assert.equal((await pedir(w, { cuerpo: COT() })).status, 409);
});

test('actorId ajeno con el rol declarado correcto (aísla la comprobación de autor) → 403', async () => {
  const w = await mundoDeCotizacion();
  w.ponerEvento('e1', { tipo: 'solicitudCreada', actor: 'comprador', actorId: AJENO });
  const r = await pedir(w, { uid: COMPRADOR, cuerpo: COT() });
  assert.equal(r.status, 403);
  assert.equal(w.enviados.length, 0);
});
