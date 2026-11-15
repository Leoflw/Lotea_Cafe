// Comprobación SIN emulador: los documentos de prueba de lotes tienen todos los campos que las reglas
// de coffeeLots evalúan y ninguno que no puedan guardar. Evita volver a probar con un lote recortado
// (un campo ausente en una regla da «Property … is undefined» y oculta lo que se quiere probar).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loteReal, perfilReal, CAMPOS_EDITABLES_DE_PERFIL, CAMPOS_OBLIGATORIOS_DE_LOTE } from './fixtures.js';

const reglas = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const bloqueLotes = reglas.slice(reglas.indexOf('match /coffeeLots/{lotId} {', reglas.indexOf('// ---------- coffeeLots/{lotId}')));
const bloqueCreate = bloqueLotes.slice(bloqueLotes.indexOf('allow create'), bloqueLotes.indexOf('allow update'));
const bloqueUpdate = bloqueLotes.slice(bloqueLotes.indexOf('allow update'), bloqueLotes.indexOf('allow delete'));

test('loteReal trae todos los campos que la regla de actualización de lotes evalúa', () => {
  const evaluados = new Set([...bloqueUpdate.matchAll(/incoming\(\)\.(\w+)/g)].map((m) => m[1]));
  const lote = loteReal();
  for (const campo of evaluados) assert.ok(campo in lote, `la regla update evalúa «${campo}» y el lote de prueba no lo tiene`);
  for (const campo of CAMPOS_OBLIGATORIOS_DE_LOTE) assert.ok(campo in lote, campo);
});

test('loteReal solo contiene campos que la regla de creación permite (esquema real)', () => {
  const permitidos = new Set([...bloqueCreate.slice(bloqueCreate.indexOf('hasOnly(['), bloqueCreate.indexOf('])')).matchAll(/'(\w+)'/g)].map((m) => m[1]));
  for (const campo of Object.keys(loteReal())) assert.ok(permitidos.has(campo), `«${campo}» no lo permite la regla create`);
  for (const campo of CAMPOS_OBLIGATORIOS_DE_LOTE) assert.ok(permitidos.has(campo), campo);
});

test('la regla de creación exige variedades (lista con al menos 1): es obligatoria en todos los lotes reales', () => {
  assert.match(bloqueCreate, /incoming\(\)\.variedades is list && incoming\(\)\.variedades\.size\(\) >= 1/);
});

const bloquePerfiles = reglas.slice(reglas.indexOf('match /sellerProfiles/{sellerId} {'));
const perfilCreate = bloquePerfiles.slice(bloquePerfiles.indexOf('allow create'), bloquePerfiles.indexOf('allow update'));
const perfilUpdate = bloquePerfiles.slice(bloquePerfiles.indexOf('allow update'), bloquePerfiles.indexOf('allow delete'));

test('perfilReal trae todos los campos que la regla de actualización de perfiles evalúa', () => {
  const evaluados = new Set([...perfilUpdate.matchAll(/incoming\(\)\.(\w+)/g)].map((m) => m[1]));
  const perfil = perfilReal();
  for (const campo of evaluados) assert.ok(campo in perfil, `la regla update evalúa «${campo}» y el perfil de prueba no lo tiene`);
});

test('perfilReal solo contiene campos que la regla de creación de perfiles permite y la app envía los editables', () => {
  const permitidos = new Set([...perfilCreate.slice(perfilCreate.indexOf('hasOnly(['), perfilCreate.indexOf('])')).matchAll(/'(\w+)'/g)].map((m) => m[1]));
  for (const campo of Object.keys(perfilReal())) assert.ok(permitidos.has(campo), `«${campo}» no lo permite la regla create`);
  const tocables = new Set([...perfilUpdate.slice(perfilUpdate.indexOf('touchesOnly(['), perfilUpdate.indexOf('])')).matchAll(/'(\w+)'/g)].map((m) => m[1]));
  // `usuarioId` se envía pero no cambia (touchesOnly mira solo los campos que cambian); el resto debe ser tocable.
  for (const campo of CAMPOS_EDITABLES_DE_PERFIL.filter((c) => c !== 'usuarioId')) assert.ok(tocables.has(campo), `«${campo}» no es tocable en update`);
});
