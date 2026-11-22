// Backend simulado para las pruebas: Firestore (REST), ImageKit, OAuth y las
// claves públicas de Firebase. Todo en memoria; no toca la red.
import { createHmac } from 'node:crypto';

export const PROYECTO = 'lotea-cafe';
export const RAIZ = '/lotea-cafe';
export const NOW_MS = 1_800_000_000_000;
export const ENV = {
  FIREBASE_PROJECT_ID: PROYECTO,
  IMAGEKIT_FOLDER_ROOT: RAIZ,
  IMAGEKIT_PRIVATE_KEY: 'private_EJEMPLO_NO_REAL=',
  CLEANUP_SERVICE_ACCOUNT_JSON: '{"simulada":true}', // las pruebas inyectan el access token por fetch
};

const b64u = (x) => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');

export async function nuevaClave(kid) {
  const par = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const jwk = await crypto.subtle.exportKey('jwk', par.publicKey);
  return { privada: par.privateKey, jwk: { ...jwk, kid, alg: 'RS256', use: 'sig' } };
}

export async function firmarToken(clave, kid, uid, extra = {}, nowMs = NOW_MS) {
  const ahora = Math.floor(nowMs / 1000);
  const cab = b64u({ alg: 'RS256', kid, typ: 'JWT' });
  const cuerpo = b64u({
    iss: `https://securetoken.google.com/${PROYECTO}`, aud: PROYECTO, sub: uid, iat: ahora - 10, exp: ahora + 3000, auth_time: ahora - 10, ...extra,
  });
  const firma = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', clave.privada, new TextEncoder().encode(`${cab}.${cuerpo}`));
  return `${cab}.${cuerpo}.${Buffer.from(firma).toString('base64url')}`;
}

const valor = (v) => {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'number') return { integerValue: String(v) };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(valor) } };
  throw new Error('tipo no soportado en la prueba');
};
const plano = (v) => {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(plano);
  return null;
};

/** Crea el mundo simulado. `fallos` permite inyectar errores por tipo de llamada. */
export function crearMundo() {
  const mundo = {
    docs: new Map(), // ruta relativa a /documents -> { fields, updateTime }
    archivos: new Map(), // fileId -> { filePath, url }
    llamadas: [], // registro { tipo, ... }
    fallos: {}, // p. ej. { imagekitBorrar: [503], firestoreConsulta: [500] } (se consume 1 por llamada)
    reloj: 0,
    txs: new Map(), // transacción -> { docs: Map(ruta -> updateTime|null), consultas: [{ from, where, limit, rutas }], abierta }
    txN: 0,
    escrituras: [], // todo lo que el Worker escribió: { ruta, campos }
    claves: null,
    fetch: null,
  };
  const tocar = () => `2026-11-08T00:00:${String(++mundo.reloj).padStart(2, '0')}.000000Z`;
  const fallo = (tipo) => (mundo.fallos[tipo]?.length ? mundo.fallos[tipo].shift() : null);
  const resp = (estado, cuerpo, cab = {}) =>
    new Response(cuerpo === undefined ? null : JSON.stringify(cuerpo), { status: estado, headers: { 'content-type': 'application/json', ...cab } });

  mundo.poner = (ruta, campos) => mundo.docs.set(ruta, { fields: Object.fromEntries(Object.entries(campos).map(([k, v]) => [k, valor(v)])), updateTime: tocar() });
  mundo.leer = (ruta) => {
    const d = mundo.docs.get(ruta);
    return d ? Object.fromEntries(Object.entries(d.fields).map(([k, v]) => [k, plano(v)])) : null;
  };
  mundo.archivo = (fileId, filePath) => mundo.archivos.set(fileId, { filePath, url: `https://ik.imagekit.io/demo${filePath}` });
  mundo.cuenta = (tipo) => mundo.llamadas.filter((l) => l.tipo === tipo).length;
  mundo.cola = (uid, fileId, campos = {}) =>
    mundo.poner(`users/${uid}/pendingFileDeletions/${fileId}`, { fileId, origen: 'lot', estado: 'pendiente', ...campos });

  const documento = (ruta) => {
    const d = mundo.docs.get(ruta);
    return { name: `projects/${PROYECTO}/databases/(default)/documents/${ruta}`, fields: d.fields, updateTime: d.updateTime };
  };
  const coincide = (doc, f) => {
    if (f.compositeFilter) {
      const { op, filters } = f.compositeFilter;
      return op === 'AND' ? filters.every((x) => coincide(doc, x)) : filters.some((x) => coincide(doc, x));
    }
    if (f.unaryFilter) {
      const a = doc.fields[f.unaryFilter.field.fieldPath];
      if (f.unaryFilter.op === 'IS_NOT_NULL') return Boolean(a) && !('nullValue' in a);
      throw new Error('filtro unario no soportado');
    }
    const { field, op, value } = f.fieldFilter;
    const actual = doc.fields[field.fieldPath];
    if (!actual) return false;
    const a = plano(actual);
    const v = plano(value);
    if (op === 'EQUAL') return a === v;
    if (op === 'ARRAY_CONTAINS') return Array.isArray(a) && a.includes(v);
    if (op === 'GREATER_THAN_OR_EQUAL') return typeof a === 'string' && a >= v;
    if (op === 'LESS_THAN_OR_EQUAL') return typeof a === 'string' && a <= v;
    throw new Error(`operador no soportado ${op}`);
  };

  mundo.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const metodo = (init.method || 'GET').toUpperCase();

    if (u.host === 'www.googleapis.com') return resp(200, { keys: [mundo.claves.jwk] }, { 'cache-control': 'max-age=3600' });
    if (u.host === 'oauth2.googleapis.com') return resp(200, { access_token: 'token-de-cuenta', expires_in: 3600 });

    if (u.host === 'api.imagekit.io') {
      const m = /^\/v1\/files\/([^/]+)(\/details)?$/.exec(u.pathname);
      const fileId = decodeURIComponent(m[1]);
      const detalles = Boolean(m[2]);
      mundo.llamadas.push({ tipo: detalles ? 'imagekitDetalles' : 'imagekitBorrar', fileId, auth: init.headers?.Authorization });
      const f = fallo(detalles ? 'imagekitDetalles' : 'imagekitBorrar');
      if (f === 'red') throw new TypeError('network');
      if (f) return resp(f, { message: 'error simulado' });
      const a = mundo.archivos.get(fileId);
      if (!a) return resp(404, { message: 'not found' });
      if (detalles) return resp(200, { fileId, filePath: a.filePath, url: a.url });
      mundo.archivos.delete(fileId);
      return new Response(null, { status: 204 });
    }

    if (u.host === 'firestore.googleapis.com') {
      const base = `/v1/projects/${PROYECTO}/databases/(default)/documents`;
      const rel = decodeURIComponent(u.pathname.slice(base.length)).replace(/^\//, '');
      if (rel === ':beginTransaction') {
        mundo.llamadas.push({ tipo: 'txInicio' });
        const f = fallo('firestoreBeginTx');
        if (f) return resp(f, {});
        const id = `tx-${++mundo.txN}`;
        mundo.txs.set(id, { docs: new Map(), consultas: [], abierta: true });
        return resp(200, { transaction: id });
      }
      if (rel === ':rollback') {
        mundo.llamadas.push({ tipo: 'txRollback' });
        const t = mundo.txs.get(JSON.parse(init.body).transaction);
        if (t) t.abierta = false;
        return resp(200, {});
      }
      if (rel === ':runQuery') {
        const q = JSON.parse(init.body).structuredQuery;
        const from = q.from[0];
        mundo.llamadas.push({ tipo: from.allDescendants ? 'consultaGlobal' : 'consultaReferencias', coleccion: from.collectionId });
        const f = fallo('firestoreConsulta');
        if (f) return resp(f, {});
        const out = [];
        for (const [ruta] of mundo.docs) {
          const seg = ruta.split('/');
          const enColeccion = from.allDescendants ? seg.at(-2) === from.collectionId : seg.length === 2 && seg[0] === from.collectionId;
          if (!enColeccion) continue;
          if (q.where && !coincide(mundo.docs.get(ruta), q.where)) continue;
          out.push({ document: documento(ruta) });
          if (out.length >= (q.limit ?? 1000)) break;
        }
        const txId = JSON.parse(init.body).transaction;
        if (txId) mundo.txs.get(txId).consultas.push({ from, where: q.where, limit: q.limit ?? 1000, rutas: out.map((o) => o.document.name.slice(`projects/${PROYECTO}/databases/(default)/documents/`.length)) });
        return resp(200, out.length ? out : [{ readTime: 'x' }]);
      }
      if (rel === ':commit') {
        const writes = JSON.parse(init.body).writes;
        mundo.llamadas.push({ tipo: 'commit', writes: writes.length });
        const f = fallo('firestoreCommit');
        if (f) return resp(f, {});
        const hook = mundo.antesDeCommit?.(writes);
        if (hook) return resp(hook, {});
        const prefijo = `projects/${PROYECTO}/databases/(default)/documents/`;
        const txId = JSON.parse(init.body).transaction;
        if (txId) {
          const t = mundo.txs.get(txId);
          if (!t || !t.abierta) return resp(409, { error: { status: 'ABORTED' } });
          t.abierta = false;
          // Conflicto si cambió un documento leído o el conjunto de resultados de una consulta leída.
          for (const [ruta, antes] of t.docs) if ((mundo.docs.get(ruta)?.updateTime ?? null) !== antes) return resp(409, { error: { status: 'ABORTED' } });
          for (const c of t.consultas) {
            const ahora = [];
            for (const [ruta] of mundo.docs) {
              const seg = ruta.split('/');
              if (!(seg.length === 2 && seg[0] === c.from.collectionId)) continue;
              if (c.where && !coincide(mundo.docs.get(ruta), c.where)) continue;
              ahora.push(ruta);
              if (ahora.length >= c.limit) break;
            }
            if (ahora.join('|') !== c.rutas.join('|')) return resp(409, { error: { status: 'ABORTED' } });
          }
        }
        // Atómico: se valida todo antes de aplicar nada.
        for (const w of writes) {
          const ruta = w.update.name.slice(prefijo.length);
          const existe = mundo.docs.has(ruta);
          const pre = w.currentDocument?.updateTime;
          if (pre !== undefined && (!existe || mundo.docs.get(ruta).updateTime !== pre)) return resp(400, { error: { status: 'FAILED_PRECONDITION' } });
          if (w.currentDocument?.exists === true && !existe) return resp(404, { error: { status: 'NOT_FOUND' } });
          if (w.currentDocument?.exists === false && existe) return resp(409, { error: { status: 'ALREADY_EXISTS' } });
        }
        for (const w of writes) {
          const ruta = w.update.name.slice(prefijo.length);
          const d = mundo.docs.get(ruta) ?? { fields: {}, updateTime: '' };
          const mascara = w.updateMask?.fieldPaths;
          if (!mascara) d.fields = { ...w.update.fields };
          else for (const campo of mascara) { if (campo in w.update.fields) d.fields[campo] = w.update.fields[campo]; else delete d.fields[campo]; }
          d.updateTime = tocar();
          mundo.docs.set(ruta, d);
          mundo.escrituras.push({ ruta, campos: mascara ?? Object.keys(w.update.fields) });
        }
        return resp(200, { writeResults: writes.map(() => ({})) });
      }
      if (metodo === 'DELETE') {
        mundo.llamadas.push({ tipo: 'borrarDoc', ruta: rel });
        const f = fallo('firestoreBorrarDoc');
        if (f) return resp(f, {});
        if (!mundo.docs.has(rel)) return resp(404, {});
        mundo.docs.delete(rel);
        mundo.escrituras.push({ ruta: rel, campos: ['*borrado*'] });
        return resp(200, {});
      }
      if (metodo === 'GET' && rel.split('/').length % 2 === 0) {
        mundo.llamadas.push({ tipo: 'leerDoc', ruta: rel });
        const txId = u.searchParams.get('transaction');
        if (txId) mundo.txs.get(txId).docs.set(rel, mundo.docs.get(rel)?.updateTime ?? null);
        return mundo.docs.has(rel) ? resp(200, documento(rel)) : resp(404, {});
      }
      if (metodo === 'GET') {
        const coleccion = rel; // users/{uid}/pendingFileDeletions
        mundo.llamadas.push({ tipo: 'listar', coleccion });
        const docs = [...mundo.docs.keys()].filter((r) => r.startsWith(`${coleccion}/`) && r.split('/').length === coleccion.split('/').length + 1).map(documento);
        return resp(200, docs.length ? { documents: docs } : {});
      }
      if (metodo === 'PATCH') {
        mundo.llamadas.push({ tipo: 'actualizar', ruta: rel });
        const f = fallo('firestoreActualizar');
        if (f) return resp(f, {});
        const d = mundo.docs.get(rel);
        const pre = u.searchParams.get('currentDocument.updateTime');
        if (!d || (pre && pre !== d.updateTime)) return resp(412, { error: { status: 'FAILED_PRECONDITION' } });
        const mascara = u.searchParams.getAll('updateMask.fieldPaths');
        const nuevos = JSON.parse(init.body).fields;
        for (const campo of mascara) {
          if (campo in nuevos) d.fields[campo] = nuevos[campo];
          else delete d.fields[campo];
        }
        d.updateTime = tocar();
        mundo.escrituras.push({ ruta: rel, campos: mascara });
        return resp(200, documento(rel));
      }
    }
    throw new Error(`petición inesperada en la prueba: ${metodo} ${url}`);
  };
  return mundo;
}

export async function mundoConClaves() {
  const mundo = crearMundo();
  mundo.claves = await nuevaClave('kid1');
  return mundo;
}

export const tokenDe = (mundo, uid, nowMs = NOW_MS) => firmarToken(mundo.claves, 'kid1', uid, {}, nowMs);
export { createHmac };
