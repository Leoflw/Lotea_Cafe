// Pruebas de users/{uid}/pendingFileDeletions y del borrado de lotes contra el EMULADOR de
// Firestore. Ejecutar desde esta carpeta (necesita Java y firebase-tools): npm install && npm test
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, updateDoc, serverTimestamp, writeBatch } from 'firebase/firestore';
import { loteReal, perfilReal, CAMPOS_EDITABLES_DE_PERFIL } from './fixtures.js';

let env;
const FID = '5f8a1c2b3d4e5f6a7b8c9d01';
const FID2 = '5f8a1c2b3d4e5f6a7b8c9d02';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'lotea-cafe-test-pending-deletions', // propio de este archivo (ver device_tokens.rules.test.js)
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
    await setDoc(doc(db, 'sellerProfiles/ana'), perfilReal()); // esquema real (fixtures.js)
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID2}`), { fileId: FID2, origen: 'lot', estado: 'enUso', intentos: 0 });
    // Lotes con el esquema REAL (fixtures.js): las reglas de actualización evalúan variedades, precioCOP, unidad…
    await setDoc(doc(db, 'coffeeLots/conFotos'), loteReal({ nombre: 'A', fotos: ['https://x/a.jpg'], fotosStoragePaths: [FID] }));
    await setDoc(doc(db, 'coffeeLots/sinFotos'), loteReal({ nombre: 'B', estado: 'borrador', fechaPublicacion: null }));
  });
});

const dbDe = (uid) => env.authenticatedContext(uid).firestore();
const cola = (db, uid, id) => doc(db, 'users', uid, 'pendingFileDeletions', id);
const solicitud = (extra = {}) => ({ fileId: FID, origen: 'lot', estado: 'pendiente', createdAt: serverTimestamp(), ...extra });

test('una persona puede encolar una foto en SU cola', async () => {
  await assertSucceeds(setDoc(cola(dbDe('ana'), 'ana', FID), solicitud()));
  await assertSucceeds(setDoc(cola(dbDe('ana'), 'ana', FID2.replace('02', '03')), solicitud({ fileId: FID2.replace('02', '03'), origen: 'profile', refId: 'ana' })));
});
test('no puede encolar en la cola de OTRA persona ni leerla', async () => {
  await assertFails(setDoc(cola(dbDe('beto'), 'ana', FID), solicitud()));
  await assertFails(getDoc(cola(dbDe('beto'), 'ana', FID2)));
  await assertSucceeds(getDoc(cola(dbDe('ana'), 'ana', FID2)));
});
test('sin sesión no puede hacer nada', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud()));
});
test('el estado inicial debe ser «pendiente»: no puede fingir «completado» ni escribir campos del Worker', async () => {
  const db = dbDe('ana');
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ estado: 'completado' })));
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ intentos: 0 })));
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ ultimoError: 'x' })));
});
test('el id debe coincidir con fileId y tener forma válida; origen y createdAt validados', async () => {
  const db = dbDe('ana');
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ fileId: FID2 })));
  await assertFails(setDoc(cola(db, 'ana', 'corto'), solicitud({ fileId: 'corto' })));
  await assertFails(setDoc(cola(db, 'ana', 'ruta/con/barras'.replace(/\//g, '_') + '!!'), solicitud({ fileId: 'ruta_con_barras!!' })));
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ origen: 'otro' })));
  await assertFails(setDoc(cola(db, 'ana', FID), solicitud({ createdAt: new Date() })));
});
test('no puede borrar solicitudes ni cambiarlas (salvo reabrir una «enUso»)', async () => {
  const db = dbDe('ana');
  await assertFails(deleteDoc(cola(db, 'ana', FID2)));
  await assertFails(updateDoc(cola(db, 'ana', FID2), { estado: 'completado' }));
  await assertFails(updateDoc(cola(db, 'ana', FID2), { estado: 'pendiente', intentos: 5, createdAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(cola(db, 'ana', FID2), { estado: 'pendiente', createdAt: serverTimestamp() }));
});
test('una solicitud que NO está «enUso» no se puede reabrir ni modificar', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/ana/pendingFileDeletions/${FID}`), { fileId: FID, origen: 'lot', estado: 'completado' });
  });
  await assertFails(updateDoc(cola(dbDe('ana'), 'ana', FID), { estado: 'pendiente', createdAt: serverTimestamp() }));
});

// ---- Un borrado directo del lote no puede saltarse la cola ----
const solicitudLote = (db, uid, id) => doc(db, 'users', uid, 'pendingLotDeletions', id);
const pedirLote = (extra = {}) => ({ lotId: 'sinFotos', estado: 'pendiente', createdAt: serverTimestamp(), ...extra });

test('borrar un lote que todavía tiene fotos se rechaza (saltarse la cola)', async () => {
  await assertFails(deleteDoc(doc(dbDe('ana'), 'coffeeLots/conFotos')));
});
test('borrar un lote sin fotos pero SIN solicitud de eliminación se rechaza (dejaría el historial sin limpiar)', async () => {
  await assertFails(deleteDoc(doc(dbDe('ana'), 'coffeeLots/sinFotos')));
});
test('un lote sin fotos y con solicitud sí se puede borrar; el de otra persona nunca', async () => {
  await assertSucceeds(setDoc(solicitudLote(dbDe('ana'), 'ana', 'sinFotos'), pedirLote()));
  await assertFails(deleteDoc(doc(dbDe('beto'), 'coffeeLots/sinFotos')));
  await assertSucceeds(deleteDoc(doc(dbDe('ana'), 'coffeeLots/sinFotos')));
});
const vaciarLote = (db, id = 'conFotos') => doc(db, 'coffeeLots', id);
const lotePedido = (id = 'conFotos') => pedirLote({ lotId: id });

// OJO: `env.withSecurityRulesDisabled(cb)` ejecuta `cb` pero DESCARTA lo que este devuelve y resuelve
// `undefined` (lo confirma su implementación). Por eso el resultado se captura en una variable; devolver
// el valor desde el callback daba `undefined` y las aserciones comparaban contra `undefined`.
const leerSinReglas = async (ruta) => {
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = await getDoc(doc(ctx.firestore(), ruta));
  });
  return snap; // DocumentSnapshot: usar .exists() y .data()
};

const LOTE = 'coffeeLots/conFotos';
// Todo lo que la operación atómica podría llegar a escribir: las dos colas, en la cola de ana y en la de beto.
const COLAS = [
  `users/ana/pendingFileDeletions/${FID}`,
  `users/beto/pendingFileDeletions/${FID}`,
  'users/ana/pendingLotDeletions/conFotos',
  'users/beto/pendingLotDeletions/conFotos',
];

/** Estado REAL guardado: el lote (datos completos) y, de cada cola, si el documento existe (true/false explícito). */
const instantanea = async () => {
  const lote = await leerSinReglas(LOTE);
  assert.equal(lote.exists(), true, 'el lote sembrado debe existir');
  const colas = {};
  for (const ruta of COLAS) colas[ruta] = (await leerSinReglas(ruta)).exists();
  return { lote: lote.data(), colas };
};

/** Tras una operación RECHAZADA no hay escrituras parciales: el lote y las cuatro colas siguen como antes. */
const assertSinCambios = async (antes, motivo) => {
  const despues = await instantanea();
  assert.deepStrictEqual(despues.lote, antes.lote, `${motivo}: el lote no debe haber cambiado`);
  assert.deepStrictEqual(despues.colas, antes.colas, `${motivo}: no debe haber solicitudes nuevas`);
  for (const [ruta, existe] of Object.entries(despues.colas)) assert.equal(existe, false, `${motivo}: no debe existir ${ruta}`);
};

/** Estado inicial sembrado por beforeEach: se comprueba (no se presupone) antes de cada escenario. */
const assertEstadoInicial = (antes) => {
  assert.deepStrictEqual(antes.lote.fotosStoragePaths, [FID]);
  assert.deepStrictEqual(antes.lote.fotos, ['https://x/a.jpg']);
  assert.deepStrictEqual(antes.lote.variedades, loteReal().variedades);
  assert.equal(antes.lote.sellerId, 'ana');
  assert.equal(antes.lote.estado, 'publicado');
  assert.equal(antes.lote.vendedorVerificado, false);
  for (const ruta of COLAS) assert.equal(antes.colas[ruta], false, `no debe existir ${ruta} al empezar`);
};

test('la app pide la eliminación en UN lote atómico: vacía fotos, encola la foto y crea la solicitud del lote', async () => {
  const antes = await instantanea();
  assertEstadoInicial(antes);
  const db = dbDe('ana');
  const batch = writeBatch(db);
  batch.update(vaciarLote(db), { estado: 'borrador', fotos: [], fotosStoragePaths: [], updatedAt: serverTimestamp() });
  batch.set(cola(db, 'ana', FID), solicitud());
  batch.set(solicitudLote(db, 'ana', 'conFotos'), lotePedido());
  await assertSucceeds(batch.commit());

  // Efectos reales: el lote queda sin fotos y en borrador, el RESTO de sus campos intacto, y las dos solicitudes existen.
  const lote = (await leerSinReglas(LOTE)).data();
  const { updatedAt: _antes, ...restoAntes } = antes.lote;
  const { updatedAt: _despues, ...restoDespues } = lote;
  assert.deepStrictEqual(restoDespues, { ...restoAntes, estado: 'borrador', fotos: [], fotosStoragePaths: [] });
  const foto = await leerSinReglas(COLAS[0]);
  assert.equal(foto.exists(), true);
  assert.equal(foto.data().estado, 'pendiente');
  assert.equal(foto.data().fileId, FID);
  const pedido = await leerSinReglas('users/ana/pendingLotDeletions/conFotos');
  assert.equal(pedido.exists(), true);
  assert.equal(pedido.data().estado, 'pendiente');
  // Nada se escribió en la cola de beto.
  assert.equal((await leerSinReglas(COLAS[1])).exists(), false);
  assert.equal((await leerSinReglas(COLAS[3])).exists(), false);

  // Y después, ya sin fotos y con su solicitud, se puede borrar el documento (lo haría el Worker o su dueño).
  await assertSucceeds(deleteDoc(vaciarLote(db)));
  assert.equal((await leerSinReglas(LOTE)).exists(), false);
});

test('esa misma operación atómica hecha por OTRA persona sobre el lote de ana se rechaza entera', async () => {
  const antes = await instantanea();
  assertEstadoInicial(antes);
  const db = dbDe('beto');
  const batch = writeBatch(db);
  batch.update(vaciarLote(db), { estado: 'borrador', fotos: [], fotosStoragePaths: [], updatedAt: serverTimestamp() });
  batch.set(cola(db, 'beto', FID), solicitud());
  batch.set(solicitudLote(db, 'beto', 'conFotos'), lotePedido());
  await assertFails(batch.commit());
  await assertSinCambios(antes, 'operación de otra persona');
});

test('la operación atómica conserva las validaciones del lote: no admite otros campos ni datos inválidos', async () => {
  const antes = await instantanea();
  assertEstadoInicial(antes);
  const intentos = {
    'vendedorVerificado: true (solo un proceso interno puede ponerlo)': { vendedorVerificado: true },
    'cambiar sellerId (cambiar de dueño)': { sellerId: 'beto' },
    'variedades vacía': { variedades: [] },
    'precioCOP en 0': { precioCOP: 0 },
    'fechaPublicacion manipulada': { fechaPublicacion: new Date() },
    'campo que no existe en el esquema': { campoInventado: 'x' },
  };
  for (const [motivo, extra] of Object.entries(intentos)) {
    const db = dbDe('ana');
    const batch = writeBatch(db);
    batch.update(vaciarLote(db), { estado: 'borrador', fotos: [], fotosStoragePaths: [], updatedAt: serverTimestamp(), ...extra });
    batch.set(cola(db, 'ana', FID), solicitud());
    batch.set(solicitudLote(db, 'ana', 'conFotos'), lotePedido());
    await assertFails(batch.commit());
    await assertSinCambios(antes, motivo); // tras CADA intento: ni lote modificado ni solicitudes en ninguna cola
  }
});

test('la operación atómica no puede colar la solicitud en la cola de OTRA persona: se rechaza entera', async () => {
  const antes = await instantanea();
  assertEstadoInicial(antes);
  const db = dbDe('ana');
  const batch = writeBatch(db);
  batch.update(vaciarLote(db), { estado: 'borrador', fotos: [], fotosStoragePaths: [], updatedAt: serverTimestamp() });
  batch.set(cola(db, 'ana', FID), solicitud());
  batch.set(solicitudLote(db, 'beto', 'conFotos'), lotePedido()); // cola de beto
  await assertFails(batch.commit());
  await assertSinCambios(antes, 'solicitud en la cola de otra persona'); // el lote no se vació y ana tampoco quedó con la foto encolada
});

test('vaciar las fotos SIN crear la solicitud del lote deja el lote sin poder borrarse', async () => {
  const db = dbDe('ana');
  const batch = writeBatch(db);
  batch.update(vaciarLote(db), { estado: 'borrador', fotos: [], fotosStoragePaths: [], updatedAt: serverTimestamp() });
  batch.set(cola(db, 'ana', FID), solicitud());
  await assertSucceeds(batch.commit());
  assert.equal((await leerSinReglas(COLAS[2])).exists(), false, 'no se creó la solicitud del lote');
  await assertFails(deleteDoc(vaciarLote(db)));
  assert.equal((await leerSinReglas(LOTE)).exists(), true, 'el lote sigue existiendo');
});
test('los perfiles siguen sin poder borrarse', async () => {
  await assertFails(deleteDoc(doc(dbDe('ana'), 'sellerProfiles/ana')));
});
test('una solicitud de foto «fallido» se puede reabrir; una «retenida» no (la revisa el Worker)', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID}`), { fileId: FID, origen: 'lot', estado: 'fallido' });
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID2.replace('02', '09')}`), { fileId: FID2.replace('02', '09'), origen: 'lot', estado: 'retenida' });
  });
  await assertSucceeds(updateDoc(cola(dbDe('ana'), 'ana', FID), { estado: 'pendiente', createdAt: serverTimestamp() }));
  await assertFails(updateDoc(cola(dbDe('ana'), 'ana', FID2.replace('02', '09')), { estado: 'pendiente', createdAt: serverTimestamp() }));
});

// ---- Reapertura de solicitudes «fallido»: solo el dueño, solo estado y createdAt ----
const FID_F = FID.replace('01', '08');
const sembrarFallidas = async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const campos = { estado: 'fallido', intentos: 6, ultimoError: 'imagekit_5xx' };
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID_F}`), { fileId: FID_F, origen: 'lot', ...campos });
    await setDoc(doc(db, 'users/ana/pendingLotDeletions/sinFotos'), { lotId: 'sinFotos', ...campos });
  });
};
const reabrir = () => ({ estado: 'pendiente', createdAt: serverTimestamp() });

test('el dueño reabre sus solicitudes «fallido» (foto y lote)', async () => {
  await sembrarFallidas();
  await assertSucceeds(updateDoc(cola(dbDe('ana'), 'ana', FID_F), reabrir()));
  await assertSucceeds(updateDoc(doc(dbDe('ana'), 'users/ana/pendingLotDeletions/sinFotos'), reabrir()));
});
test('OTRA persona no puede reabrir las solicitudes de ana (foto ni lote)', async () => {
  await sembrarFallidas();
  await assertFails(updateDoc(cola(dbDe('beto'), 'ana', FID_F), reabrir()));
  await assertFails(updateDoc(doc(dbDe('beto'), 'users/ana/pendingLotDeletions/sinFotos'), reabrir()));
  const anonimo = env.unauthenticatedContext().firestore();
  await assertFails(updateDoc(cola(anonimo, 'ana', FID_F), reabrir()));
});
test('al reabrir no puede reiniciar el contador, borrar el error ni cambiar otros campos (lo hace el Worker)', async () => {
  await sembrarFallidas();
  const foto = cola(dbDe('ana'), 'ana', FID_F);
  const lote = doc(dbDe('ana'), 'users/ana/pendingLotDeletions/sinFotos');
  for (const ref of [foto, lote]) {
    await assertFails(updateDoc(ref, { ...reabrir(), intentos: 0 }));
    await assertFails(updateDoc(ref, { ...reabrir(), ultimoError: null }));
    await assertFails(updateDoc(ref, { ...reabrir(), refId: 'otro' }));
    await assertFails(updateDoc(ref, { estado: 'completado', createdAt: serverTimestamp() }));
  }
});
test('una solicitud «completado» (foto o lote) no se puede reabrir', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID_F}`), { fileId: FID_F, origen: 'lot', estado: 'completado' });
    await setDoc(doc(db, 'users/ana/pendingLotDeletions/sinFotos'), { lotId: 'sinFotos', estado: 'completado' });
  });
  await assertFails(updateDoc(cola(dbDe('ana'), 'ana', FID_F), reabrir()));
  await assertFails(updateDoc(doc(dbDe('ana'), 'users/ana/pendingLotDeletions/sinFotos'), reabrir()));
});
test('reabrir una solicitud no permite tocar el historial de fotos (loteFoto) ni borrar la solicitud', async () => {
  await sembrarFallidas();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'interestRequests/c1_sinFotos'), { compradorId: 'c1', sellerId: 'ana', coffeeLotId: 'sinFotos', estado: 'pendiente', loteFoto: 'https://ik.imagekit.io/demo/a.jpg' });
  });
  const db = dbDe('ana');
  await assertFails(updateDoc(doc(db, 'interestRequests/c1_sinFotos'), { loteFoto: null, updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(cola(db, 'ana', FID_F)));
  await assertFails(deleteDoc(doc(db, 'users/ana/pendingLotDeletions/sinFotos')));
});

// ---- Guardado del perfil del vendedor: operación atómica + reapertura de una solicitud «fallido» ----
const PERFIL = 'sellerProfiles/ana';
const FID_NUEVA_FOTO = FID.replace('01', '11');
const FID_FALLIDA = FID.replace('01', '12');
const FID_COMPLETADA = FID.replace('01', '13');
const URL_VIEJA = 'https://ik.imagekit.io/demo/lotea-cafe/users/ana/profile/vieja.jpg';
const URL_NUEVA = 'https://ik.imagekit.io/demo/lotea-cafe/users/ana/profile/nueva.jpg';
const RUTAS_PERFIL = [
  `users/ana/pendingFileDeletions/${FID}`,
  `users/ana/pendingFileDeletions/${FID_FALLIDA}`,
  `users/ana/pendingFileDeletions/${FID_COMPLETADA}`,
  `users/beto/pendingFileDeletions/${FID_FALLIDA}`,
];

/** Lo que `SellerRepository.guardarPerfil` envía: los campos editables completos (los sin cambio, con su valor) + updatedAt. */
const perfilEditable = (cambios = {}) => {
  const actual = perfilReal();
  const editable = Object.fromEntries(CAMPOS_EDITABLES_DE_PERFIL.map((c) => [c, actual[c]]));
  return { ...editable, fotoPrincipal: URL_VIEJA, fotoPrincipalStoragePath: FID, ...cambios, updatedAt: serverTimestamp() };
};
const reabrirSolicitud = () => ({ estado: 'pendiente', createdAt: serverTimestamp() });

const sembrarPerfil = async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, PERFIL), perfilReal({ fotoPrincipal: URL_VIEJA, fotoPrincipalStoragePath: FID }));
    const falla = { origen: 'profile', refId: 'ana', intentos: 6, ultimoError: 'imagekit_credenciales' };
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID_FALLIDA}`), { fileId: FID_FALLIDA, estado: 'fallido', ...falla });
    await setDoc(doc(db, `users/ana/pendingFileDeletions/${FID_COMPLETADA}`), { fileId: FID_COMPLETADA, estado: 'completado', ...falla });
    await setDoc(doc(db, `users/beto/pendingFileDeletions/${FID_FALLIDA}`), { fileId: FID_FALLIDA, estado: 'fallido', ...falla });
  });
};
const estadoPerfil = async () => {
  const colas = {};
  for (const ruta of RUTAS_PERFIL) {
    const snap = await leerSinReglas(ruta);
    colas[ruta] = snap.exists() ? snap.data() : false;
  }
  const perfil = await leerSinReglas(PERFIL);
  assert.equal(perfil.exists(), true);
  return { perfil: perfil.data(), colas };
};

test('guardar el perfil es UNA operación atómica permitida: actualiza el perfil, encola la foto retirada y reabre la solicitud «fallido»', async () => {
  await sembrarPerfil();
  const antes = await estadoPerfil();
  assert.equal(antes.perfil.fotoPrincipalStoragePath, FID);
  assert.equal(antes.colas[RUTAS_PERFIL[0]], false, 'la foto vieja aún no está encolada');
  assert.equal(antes.colas[RUTAS_PERFIL[1]].estado, 'fallido');

  const db = dbDe('ana');
  const batch = writeBatch(db);
  batch.update(doc(db, PERFIL), perfilEditable({ fotoPrincipal: URL_NUEVA, fotoPrincipalStoragePath: FID_NUEVA_FOTO }));
  batch.set(cola(db, 'ana', FID), solicitud()); // la foto que se retira ahora
  batch.update(cola(db, 'ana', FID_FALLIDA), reabrirSolicitud()); // la antigua que falló
  await assertSucceeds(batch.commit());

  const despues = await estadoPerfil();
  assert.equal(despues.perfil.fotoPrincipalStoragePath, FID_NUEVA_FOTO);
  assert.equal(despues.perfil.fotoPrincipal, URL_NUEVA);
  for (const campo of ['verificado', 'calificacionPromedio', 'numOperaciones', 'usuarioId']) assert.deepStrictEqual(despues.perfil[campo], antes.perfil[campo], campo);
  assert.equal(despues.colas[RUTAS_PERFIL[0]].estado, 'pendiente');
  assert.equal(despues.colas[RUTAS_PERFIL[0]].fileId, FID);
  const reabierta = despues.colas[RUTAS_PERFIL[1]];
  assert.equal(reabierta.estado, 'pendiente');
  // La reapertura solo cambia estado y createdAt: el contador y el último error siguen siendo del Worker.
  assert.equal(reabierta.intentos, 6);
  assert.equal(reabierta.ultimoError, 'imagekit_credenciales');
  // No se tocó ni la solicitud completada ni la de otra persona.
  assert.deepStrictEqual(despues.colas[RUTAS_PERFIL[2]], antes.colas[RUTAS_PERFIL[2]]);
  assert.deepStrictEqual(despues.colas[RUTAS_PERFIL[3]], antes.colas[RUTAS_PERFIL[3]]);
});

test('esa operación atómica NO admite campos adicionales ni reaperturas indebidas: se rechaza entera sin escrituras parciales', async () => {
  await sembrarPerfil();
  const antes = await estadoPerfil();
  const intentos = {
    'reabrir reiniciando intentos (campo del Worker)': (db, b) => b.update(cola(db, 'ana', FID_FALLIDA), { ...reabrirSolicitud(), intentos: 0 }),
    'reabrir borrando ultimoError (campo del Worker)': (db, b) => b.update(cola(db, 'ana', FID_FALLIDA), { ...reabrirSolicitud(), ultimoError: null }),
    'reabrir cambiando el refId': (db, b) => b.update(cola(db, 'ana', FID_FALLIDA), { ...reabrirSolicitud(), refId: 'otro' }),
    'reabrir una solicitud «completado»': (db, b) => b.update(cola(db, 'ana', FID_COMPLETADA), reabrirSolicitud()),
    'reabrir la solicitud de OTRA persona': (db, b) => b.update(cola(db, 'beto', FID_FALLIDA), reabrirSolicitud()),
    'encolar con un campo del Worker': (db, b) => b.set(cola(db, 'ana', FID), solicitud({ intentos: 0 })),
    'poner verificado en el perfil': (db, b) => b.update(doc(db, PERFIL), perfilEditable({ verificado: true })),
    'cambiar la calificación del perfil': (db, b) => b.update(doc(db, PERFIL), perfilEditable({ calificacionPromedio: 5 })),
    'añadir un campo inventado al perfil': (db, b) => b.update(doc(db, PERFIL), perfilEditable({ campoInventado: 'x' })),
  };
  for (const [motivo, malo] of Object.entries(intentos)) {
    const db = dbDe('ana');
    const batch = writeBatch(db);
    batch.update(doc(db, PERFIL), perfilEditable({ fotoPrincipal: URL_NUEVA, fotoPrincipalStoragePath: FID_NUEVA_FOTO })); // parte legítima
    batch.update(cola(db, 'ana', FID_FALLIDA), reabrirSolicitud()); // parte legítima
    malo(db, batch);
    await assertFails(batch.commit());
    const despues = await estadoPerfil();
    assert.deepStrictEqual(despues.perfil, antes.perfil, `${motivo}: el perfil no debe haber cambiado`);
    assert.deepStrictEqual(despues.colas, antes.colas, `${motivo}: ninguna cola debe haber cambiado`);
  }
});

test('desde la app no se puede borrar ninguna solicitud ni el perfil (ni como parte del guardado)', async () => {
  await sembrarPerfil();
  const db = dbDe('ana');
  await assertFails(deleteDoc(cola(db, 'ana', FID_FALLIDA)));
  await assertFails(deleteDoc(doc(db, PERFIL)));
  const antes = await estadoPerfil();
  assert.equal(antes.colas[RUTAS_PERFIL[1]].estado, 'fallido');
});
