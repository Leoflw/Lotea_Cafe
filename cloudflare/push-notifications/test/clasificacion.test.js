import test from 'node:test';
import assert from 'node:assert/strict';
import { CODIGOS_CAUSA, clasificarExcepcion, sanear } from '../src/diagnostico.js';

test('clasificarExcepcion devuelve solo valores de conjuntos cerrados', () => {
  assert.deepEqual(clasificarExcepcion(new TypeError('Illegal invocation: …')), { errorNombre: 'TypeError', errorCodigo: 'invocacion_ilegal' });
  assert.deepEqual(clasificarExcepcion(new DOMException('m', 'AbortError')), { errorNombre: 'DOMException', errorCodigo: 'abortado' });
  assert.deepEqual(clasificarExcepcion(new DOMException('m', 'TimeoutError')), { errorNombre: 'DOMException', errorCodigo: 'timeout' });
  assert.deepEqual(clasificarExcepcion(Object.assign(new Error('x'), { code: 'ENOTFOUND' })), { errorNombre: 'Error', errorCodigo: 'ENOTFOUND' });
  assert.deepEqual(clasificarExcepcion(Object.assign(new Error('x'), { cause: { code: 'UND_ERR_SOCKET' } })), { errorNombre: 'Error', errorCodigo: 'UND_ERR_SOCKET' });
  for (const raro of [null, undefined, 'texto', 42, {}, { message: 5 }]) {
    const r = clasificarExcepcion(raro);
    assert.ok(['otro', 'Error', 'TypeError'].includes(r.errorNombre) || r.errorNombre === 'otro');
    assert.ok(CODIGOS_CAUSA.has(r.errorCodigo));
  }
});

test('un código desconocido (p. ej. con un secreto) NO se copia: se clasifica por patrón o «sin_clasificar»', () => {
  const r = clasificarExcepcion(Object.assign(new TypeError('texto SECRETO'), { code: 'ya29.SECRETO', cause: { code: 'tokV1_SECRETO' } }));
  assert.deepEqual(r, { errorNombre: 'TypeError', errorCodigo: 'sin_clasificar' });
  assert.equal(JSON.stringify(r).includes('SECRETO'), false);
});

test('el mensaje solo sirve de entrada: no aparece en la salida aunque coincida con un patrón', () => {
  const r = clasificarExcepcion(new TypeError('Illegal invocation SECRETO-EN-EL-MENSAJE'));
  assert.equal(JSON.stringify(r).includes('SECRETO'), false);
  assert.equal(r.errorCodigo, 'invocacion_ilegal');
});

test('sanear valida errorNombre y errorCodigo contra sus listas', () => {
  assert.deepEqual(sanear({ errorNombre: 'TypeError', errorCodigo: 'invocacion_ilegal' }), { errorNombre: 'TypeError', errorCodigo: 'invocacion_ilegal' });
  assert.deepEqual(sanear({ errorNombre: 'SECRETO', errorCodigo: 'SECRETO' }), { errorNombre: 'otro', errorCodigo: 'otro' });
  assert.deepEqual(sanear({ errorNombre: 5, errorCodigo: 5 }), {});
});
