// Utilidades de prueba: simulan Google (claves públicas de Firebase, OAuth, Firestore
// y FCM) con un `fetch` inyectado. Ninguna prueba toca la red ni usa credenciales
// reales: la «cuenta de servicio» es una clave RSA generada al vuelo.
import { resetJwksCache } from '../src/firebase.js';
import { resetAuthCache } from '../src/google-auth.js';
import { resetLimitador } from '../src/index.js';

export const PROJECT = 'lotea-cafe';
export const NOW_MS = 1_800_000_000_000;
export const NOW = Math.floor(NOW_MS / 1000);
export const ENDPOINT = 'https://push.example.workers.dev/notify';

export const COMPRADOR = 'uid_comprador';
export const VENDEDOR = 'uid_vendedor';
export const AJENO = 'uid_ajeno';
export const CONEXION = `${COMPRADOR}_lot1`;

const b64u = (x) => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');
const algRsa = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };
const nuevoPar = () =>
  crypto.subtle.generateKey({ ...algRsa, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) }, true, ['sign', 'verify']);

export async function nuevaClaveGoogle(kid) {
  const par = await nuevoPar();
  const jwk = await crypto.subtle.exportKey('jwk', par.publicKey);
  return { privada: par.privateKey, jwk: { ...jwk, kid, alg: 'RS256', use: 'sig' } };
}

export async function firmarIdToken(clave, kid, payload) {
  const h = b64u({ alg: 'RS256', kid, typ: 'JWT' });
  const p = b64u(payload);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', clave, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${Buffer.from(sig).toString('base64url')}`;
}

export const payloadBase = (extra = {}) => ({
  iss: `https://securetoken.google.com/${PROJECT}`,
  aud: PROJECT,
  auth_time: NOW - 100,
  iat: NOW - 100,
  exp: NOW + 3000,
  sub: COMPRADOR,
  ...extra,
});

/** Cuenta de servicio FALSA con clave RSA generada ahora (no es ninguna credencial real). */
export async function nuevaCuentaDeServicio(proyecto = PROJECT) {
  const par = await nuevoPar();
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', par.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\n${der.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
  return {
    json: JSON.stringify({ type: 'service_account', project_id: proyecto, client_email: 'push@lotea-cafe.iam.gserviceaccount.com', private_key: pem }),
    publica: par.publicKey,
  };
}

// ---- Documentos REST ----
export const s = (v) => ({ stringValue: v });
export const t = (ms) => ({ timestampValue: new Date(ms).toISOString() });

export const URL_FIRESTORE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/`;
const respuesta = (estado, cuerpo) => new Response(JSON.stringify(cuerpo ?? {}), { status: estado, headers: { 'Content-Type': 'application/json' } });
const errorGoogle = (estado, status, extra = {}) => respuesta(estado, { error: { code: estado, status, message: status, ...extra } });

/** Respuestas de FCM reutilizables. */
export const FCM = {
  ok: () => respuesta(200, { name: 'projects/lotea-cafe/messages/0:1' }),
  noRegistrado: () =>
    errorGoogle(404, 'NOT_FOUND', { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] }),
  tokenMalFormado: () =>
    errorGoogle(400, 'INVALID_ARGUMENT', {
      details: [
        { '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.token', description: 'Invalid registration token' }] },
        { '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'INVALID_ARGUMENT' },
      ],
    }),
  cargaInvalida: () =>
    errorGoogle(400, 'INVALID_ARGUMENT', {
      details: [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.android.ttl', description: 'mal' }] }],
    }),
  noEncontradoGenerico: () => errorGoogle(404, 'NOT_FOUND'), // p. ej. proyecto mal escrito: NO es «token inexistente»
  noDisponible: () => errorGoogle(503, 'UNAVAILABLE'),
  cuota: () => errorGoogle(429, 'RESOURCE_EXHAUSTED', { details: [{ errorCode: 'QUOTA_EXCEEDED' }] }),
  interno: () => errorGoogle(500, 'INTERNAL'),
  sinPermiso: () => errorGoogle(403, 'PERMISSION_DENIED'),
  remitenteDistinto: () =>
    errorGoogle(403, 'PERMISSION_DENIED', { details: [{ errorCode: 'SENDER_ID_MISMATCH' }] }),
  noAutenticado: () => errorGoogle(401, 'UNAUTHENTICATED'),
};

/**
 * Mundo simulado. Lleva Firestore en memoria con tres comprobaciones útiles:
 *  - las lecturas con ID token de usuario NO pueden ver deviceTokens ni pushDedupe;
 *  - las escrituras solo se aceptan con el access token de la cuenta de servicio;
 *  - se cuentan las llamadas para comprobar la caché del token OAuth.
 */
export class Mundo {
  constructor() {
    this.docs = new Map(); // ruta relativa → { fields, updateTime }
    this.version = 1;
    this.enviados = []; // mensajes FCM aceptados o intentados: { token, cuerpo }
    this.respuestasFcm = new Map(); // token → función → Response (o Error para fallo de red)
    this.respuestaFcmPorDefecto = () => FCM.ok();
    this.llamadasOauth = 0;
    this.accesos = []; // { metodo, ruta, quien: 'usuario'|'cuenta' }
    this.fallosOauth = null; // función → Response
    this.rechazar401Una = false;
    this.accessTokens = new Set();
    // Inyección de fallos para las pruebas de diagnóstico:
    this.fallosFirestore = []; // { metodo, ruta: RegExp, quien?: 'usuario'|'cuenta', respuesta: () => Response }
    this.redCaida = new Set(); // nombres de host cuyo fetch lanza una excepción de red
    this.jwksFallo = null; // () => Response para las claves públicas de Firebase
  }

  async iniciar() {
    this.claveGoogle = await nuevaClaveGoogle('kid-1');
    this.sa = await nuevaCuentaDeServicio();
    this.env = { FIREBASE_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT_JSON: this.sa.json, ANDROID_CHANNEL_ID: 'lotea_mensajes_cotizaciones' };
    resetJwksCache();
    resetAuthCache();
    resetLimitador();
    return this;
  }

  // ---- siembra de datos ----
  poner(ruta, fields) {
    this.docs.set(ruta, { fields, updateTime: this._ut() });
  }
  _ut() {
    return new Date(NOW_MS + this.version++).toISOString();
  }
  ponerConexion({ estado = 'aceptada', ultimoMensajeId = 'm1', ultimoMensajeDe = COMPRADOR } = {}) {
    this.poner(`interestRequests/${CONEXION}`, {
      compradorId: s(COMPRADOR), sellerId: s(VENDEDOR), coffeeLotId: s('lot1'), estado: s(estado),
      ...(ultimoMensajeId ? { ultimoMensajeId: s(ultimoMensajeId), ultimoMensajeDe: s(ultimoMensajeDe) } : {}),
    });
  }
  ponerMensaje(id = 'm1', { senderId = COMPRADOR, edadMs = 2000 } = {}) {
    this.poner(`chats/${CONEXION}/messages/${id}`, { senderId: s(senderId), texto: s('SECRETO-DEL-CHAT'), createdAt: t(NOW_MS - edadMs) });
  }
  ponerCotizacion(id = 'q1') {
    this.poner(`quotes/${id}`, { compradorId: s(COMPRADOR), sellerId: s(VENDEDOR), estado: s('solicitudPendiente') });
  }
  ponerEvento(id, { tipo = 'solicitudCreada', actor = 'comprador', actorId = COMPRADOR, quote = 'q1', edadMs = 2000 } = {}) {
    this.poner(`quotes/${quote}/events/${id}`, { tipo: s(tipo), actor: s(actor), actorId: s(actorId), fecha: t(NOW_MS - edadMs) });
  }
  ponerDispositivo(uid, id, token, edadMs = 1000) {
    this.poner(`users/${uid}/deviceTokens/${id}`, { token: s(token), plataforma: s('android'), updatedAt: t(NOW_MS - edadMs) });
  }
  tokenValido(prefijo) {
    return `${prefijo}_`.padEnd(40, 'x');
  }
  dispositivos(uid) {
    return [...this.docs.keys()].filter((k) => k.startsWith(`users/${uid}/deviceTokens/`));
  }
  dedupe() {
    return [...this.docs.entries()].filter(([k]) => k.startsWith('pushDedupe/'));
  }

  async idToken(uid = COMPRADOR, extra = {}) {
    return firmarIdToken(this.claveGoogle.privada, 'kid-1', payloadBase({ sub: uid, ...extra }));
  }

  // ---- fetch simulado ----
  fetch = async (url, init = {}) => {
    const u = new URL(String(url));
    const metodo = init.method || 'GET';
    if (this.redCaida.has(u.hostname)) throw new TypeError('fetch failed: RED-CAIDA-SECRETO');
    if (u.hostname === 'www.googleapis.com') {
      if (this.jwksFallo) return this.jwksFallo();
      return new Response(JSON.stringify({ keys: [this.claveGoogle.jwk] }), { headers: { 'cache-control': 'public, max-age=3600' } });
    }
    if (u.hostname === 'oauth2.googleapis.com') return this._oauth(init);
    if (u.hostname === 'fcm.googleapis.com') return this._fcm(init);
    if (u.hostname === 'firestore.googleapis.com') return this._firestore(u, metodo, init);
    throw new Error(`fetch inesperado: ${u}`);
  };

  async _oauth(init) {
    this.llamadasOauth++;
    if (this.fallosOauth) return this.fallosOauth();
    const assertion = new URLSearchParams(init.body).get('assertion');
    const [h, p, f] = assertion.split('.');
    const valido = await crypto.subtle.verify(algRsa, this.sa.publica, Buffer.from(f, 'base64url'), new TextEncoder().encode(`${h}.${p}`));
    const claims = JSON.parse(Buffer.from(p, 'base64url'));
    if (!valido || claims.iss !== 'push@lotea-cafe.iam.gserviceaccount.com' || claims.aud !== 'https://oauth2.googleapis.com/token'
      || !claims.scope.includes('firebase.messaging') || !claims.scope.includes('datastore') || claims.exp - claims.iat > 3600) {
      return respuesta(400, { error: 'invalid_grant' });
    }
    const token = `at_${this.llamadasOauth}`;
    this.accessTokens.add(token);
    return respuesta(200, { access_token: token, expires_in: 3599, token_type: 'Bearer' });
  }

  _quien(init) {
    const auth = (init.headers || {}).Authorization || '';
    const bearer = auth.replace('Bearer ', '');
    if (this.accessTokens.has(bearer)) return 'cuenta';
    if (bearer.split('.').length === 3) return 'usuario';
    return null;
  }

  async _fcm(init) {
    if (this._quien(init) !== 'cuenta') return FCM.noAutenticado();
    if (this.rechazar401Una) {
      this.rechazar401Una = false;
      this.accessTokens.clear(); // el token cacheado deja de valer
      return FCM.noAutenticado();
    }
    const cuerpo = JSON.parse(init.body);
    const token = cuerpo.message.token;
    this.enviados.push({ token, cuerpo });
    const fn = this.respuestasFcm.get(token) ?? this.respuestaFcmPorDefecto;
    const r = fn();
    if (r instanceof Error) throw r;
    return r;
  }

  _firestore(u, metodo, init) {
    const ruta = decodeURIComponent(u.pathname.split('/documents/')[1]);
    const quien = this._quien(init);
    this.accesos.push({ metodo, ruta, quien });
    for (const f of this.fallosFirestore) {
      if (f.metodo === metodo && f.ruta.test(ruta) && (f.quien ?? quien) === quien) return f.respuesta();
    }
    if (!quien) return errorGoogle(401, 'UNAUTHENTICATED');
    const privado = ruta.includes('/deviceTokens') || ruta.startsWith('pushDedupe');
    if (quien === 'usuario' && (metodo !== 'GET' || privado)) return errorGoogle(403, 'PERMISSION_DENIED');
    const segmentos = ruta.split('/');
    const esColeccion = segmentos.length % 2 === 1;
    const pre = u.searchParams.get('currentDocument.updateTime');
    const preExiste = u.searchParams.get('currentDocument.exists');
    const nombre = (r) => `projects/${PROJECT}/databases/(default)/documents/${r}`;

    if (metodo === 'GET' && esColeccion) {
      const hijos = [...this.docs.entries()].filter(([k]) => k.startsWith(`${ruta}/`) && !k.slice(ruta.length + 1).includes('/'));
      return respuesta(200, hijos.length ? { documents: hijos.map(([k, d]) => ({ name: nombre(k), fields: d.fields, updateTime: d.updateTime })) } : {});
    }
    if (metodo === 'GET') {
      const d = this.docs.get(ruta);
      return d ? respuesta(200, { name: nombre(ruta), fields: d.fields, updateTime: d.updateTime }) : errorGoogle(404, 'NOT_FOUND');
    }
    if (metodo === 'POST') {
      const id = u.searchParams.get('documentId');
      const rutaNueva = `${ruta}/${id}`;
      if (this.docs.has(rutaNueva)) return errorGoogle(409, 'ALREADY_EXISTS');
      this.poner(rutaNueva, JSON.parse(init.body).fields);
      return respuesta(200, { name: nombre(rutaNueva) });
    }
    const d = this.docs.get(ruta);
    if (pre && (!d || d.updateTime !== pre)) return errorGoogle(400, 'FAILED_PRECONDITION');
    if (preExiste === 'true' && !d) return errorGoogle(404, 'NOT_FOUND');
    if (metodo === 'PATCH') {
      if (!d) return errorGoogle(404, 'NOT_FOUND');
      this.poner(ruta, { ...d.fields, ...JSON.parse(init.body).fields });
      return respuesta(200, {});
    }
    if (metodo === 'DELETE') {
      if (!d) return errorGoogle(404, 'NOT_FOUND');
      this.docs.delete(ruta);
      return respuesta(200, {});
    }
    return errorGoogle(405, 'METHOD_NOT_ALLOWED');
  }
}

/** Prepara un mundo con una conexión aceptada, un mensaje del comprador y un dispositivo del vendedor. */
export async function mundoDeChat() {
  const w = await new Mundo().iniciar();
  w.ponerConexion();
  w.ponerMensaje('m1');
  w.ponerDispositivo(VENDEDOR, 'dev1', w.tokenValido('tokV1'));
  return w;
}

/** Prepara un mundo con una cotización y un dispositivo para cada parte. */
export async function mundoDeCotizacion() {
  const w = await new Mundo().iniciar();
  w.ponerCotizacion('q1');
  w.ponerDispositivo(VENDEDOR, 'devV', w.tokenValido('tokV'));
  w.ponerDispositivo(COMPRADOR, 'devC', w.tokenValido('tokC'));
  return w;
}

/**
 * Emula la comprobación de `this` de `fetch` en Cloudflare Workers (workerd): llamado como método de
 * otro objeto (`obj.fetch(...)`) lanza «TypeError: Illegal invocation: function called with incorrect
 * `this` reference»; llamado como función simple funciona. Los mocks de flecha del resto de pruebas
 * ignoran `this`, por eso esa clase de fallo no se veía. Doc: developers.cloudflare.com/workers/observability/errors
 * (sección «Illegal invocation»). NO es el runtime real: confirmar tras desplegar.
 */
export function fetchEstricto(base) {
  return function fetchEstrictoDeWorkers(...args) {
    if (this !== undefined && this !== globalThis) {
      throw new TypeError('Illegal invocation: function called with incorrect `this` reference.');
    }
    return base(...args);
  };
}
