// Cloudflare Worker — notificaciones push de Lotea Café (FCM HTTP v1).
//
// Servicio INDEPENDIENTE del Worker de ImageKit (cloudflare/imagekit-upload-auth):
// código, wrangler.toml, secretos y despliegue propios.
//
//   POST /notify
//   Authorization: Bearer <ID token de Firebase Authentication>
//   {"tipo":"chatMessage","connectionId":"…","messageId":"…"}
//   {"tipo":"quoteEvent","quoteId":"…","eventId":"…"}
//
// El cliente NUNCA indica a quién avisar ni qué texto enviar: el Worker verifica
// el token, comprueba en Firestore que el mensaje o evento es real y suyo,
// deduce el destinatario, lee sus dispositivos y envía un aviso genérico.

import { comprobarConectividad, diagnosticoActivo, tokenCorrecto } from './conectividad.js';
import { claveDeEvento, liberar, marcarEnviado, reclamar } from './dedupe.js';
import { nombreSeguro, sanear } from './diagnostico.js';
import { ConfigError, RequestError, UpstreamError } from './errores.js';
import { resolverChat, resolverCotizacion } from './eventos.js';
import { construirMensaje, enviarDetallado } from './fcm.js';
import { AuthError, verifyIdToken } from './firebase.js';
import { borrarDispositivo, listarDispositivos } from './firestore.js';
import { MAX_BODY_BYTES, validarCuerpo } from './validar.js';

// Limitador «de mejor esfuerzo» en memoria (no es global entre instancias). La
// protección real contra repeticiones es la deduplicación persistente.
const LIMITE = { max: 60, ventanaMs: 10 * 60 * 1000 }; // 60 avisos / 10 min / usuario
const usos = new Map();
export function resetLimitador() {
  usos.clear();
}
function excedeLimite(uid, nowMs) {
  const recientes = (usos.get(uid) || []).filter((t) => nowMs - t < LIMITE.ventanaMs);
  if (recientes.length >= LIMITE.max) {
    usos.set(uid, recientes);
    return true;
  }
  recientes.push(nowMs);
  usos.set(uid, recientes);
  if (usos.size > 5000) usos.clear();
  return false;
}

function json(estado, cuerpo) {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
const error = (estado, mensaje, extra = {}) => json(estado, { error: mensaje, ...extra });

export async function handle(request, env, deps = {}) {
  // `fetch` global envuelto: así nunca se invoca con un `this` ajeno (ver google-auth.js, fetchConCuenta).
  const fetchFn = deps.fetch ?? ((entrada, opciones) => fetch(entrada, opciones));
  const nowMs = deps.nowMs ?? Date.now();
  const log = deps.log ?? ((e) => console.log(JSON.stringify(e)));
  const url = new URL(request.url);

  if (url.protocol !== 'https:' && env.ALLOW_HTTP !== 'true') return error(400, 'Se requiere HTTPS.');
  // Comprobación de conectividad: SOLO existe si el Worker tiene el secreto DIAGNOSTICO_TOKEN (ver conectividad.js).
  // Con un token ausente o incorrecto responde igual que una ruta inexistente.
  if (url.pathname === '/diagnostico' && request.method === 'GET' && diagnosticoActivo(env)) {
    const bearer = /^Bearer (.+)$/.exec(request.headers.get('Authorization') || '');
    if (!bearer || !(await tokenCorrecto(bearer[1].trim(), env.DIAGNOSTICO_TOKEN))) return error(404, 'No encontrado.');
    if (!env.FIREBASE_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT_JSON) return error(500, 'El Worker no está configurado.');
    const informe = await comprobarConectividad(env, env.FIREBASE_PROJECT_ID, { fetchFn, nowMs });
    log({ evento: 'diagnostico', ok: informe.ok, pasos: informe.pasos });
    return json(200, informe);
  }
  if (request.method !== 'POST') return error(405, 'Método no permitido.');
  if (url.pathname !== '/notify') return error(404, 'No encontrado.');
  if (!env.FIREBASE_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT_JSON) return error(500, 'El Worker no está configurado.');
  const proyecto = env.FIREBASE_PROJECT_ID;

  // 1) Autenticación: token de Firebase validado criptográficamente.
  const m = /^Bearer (.+)$/.exec(request.headers.get('Authorization') || '');
  if (!m) return error(401, 'Falta el token de sesión.');
  const idToken = m[1].trim();
  let payload;
  try {
    payload = await verifyIdToken(idToken, { projectId: proyecto, fetchFn, nowMs });
  } catch (e) {
    if (e instanceof AuthError) return error(401, 'Sesión no válida. Inicia sesión de nuevo.');
    // Diagnóstico: aquí solo llegan fallos al pedir las claves públicas de Firebase (u otro imprevisto).
    log({ evento: 'notify_error', clase: 'upstream', ...sanear(e instanceof UpstreamError ? e.diag : { etapa: 'verificar_id_token', servicio: 'firebase_auth' }) });
    return error(503, 'No se pudo validar la sesión. Inténtalo de nuevo.');
  }
  const uid = payload.sub; // El UID sale del token, nunca del cuerpo.

  const contexto = { env, fetchFn, nowMs };
  let claim = null; // id del registro de deduplicación que esta petición posee
  let etapa = 'validar_peticion'; // solo para el registro de diagnóstico
  let tipo; // chatMessage | quoteEvent, solo para el registro de diagnóstico
  try {
    // 2) Cuerpo estricto.
    const texto = await request.text();
    if (new TextEncoder().encode(texto).length > MAX_BODY_BYTES) return error(413, 'Petición demasiado grande.');
    let crudo;
    try {
      crudo = JSON.parse(texto);
    } catch {
      return error(400, 'El cuerpo debe ser JSON.');
    }
    const cuerpo = validarCuerpo(crudo);
    tipo = cuerpo.tipo;

    if (excedeLimite(uid, nowMs)) return error(429, 'Demasiados avisos seguidos. Espera unos minutos.');

    // 3) El acontecimiento es real y es del usuario; se deduce el destinatario.
    const ctx = { proyecto, uid, idToken, fetchFn, nowMs };
    etapa = 'firestore_leer_evento';
    const evento = cuerpo.tipo === 'chatMessage' ? await resolverChat(ctx, cuerpo) : await resolverCotizacion(ctx, cuerpo);

    // 4) Dispositivos del destinatario (cuenta de servicio).
    etapa = 'firestore_listar_dispositivos';
    const dispositivos = await listarDispositivos(env, proyecto, evento.destinatarioUid, contexto);
    if (dispositivos.length === 0) return json(200, { estado: 'sinDispositivos', enviados: 0 });

    // 5) Deduplicación persistente.
    etapa = 'firestore_dedupe';
    const id = await claveDeEvento(...evento.clave);
    const reclamo = await reclamar(env, proyecto, id, cuerpo.tipo, contexto);
    if (reclamo === 'duplicado') return json(200, { estado: 'duplicado', enviados: 0 });
    if (reclamo === 'enCurso') return json(202, { estado: 'enCurso', enviados: 0 });
    claim = id;

    // 6) Envío a cada dispositivo (máx. 10, en paralelo).
    etapa = 'fcm_enviar';
    const resultados = await Promise.all(
      dispositivos.map(async (d) => {
        const { resultado, diag } = await enviarDetallado(env, proyecto, construirMensaje({ token: d.token, ruta: evento.ruta, id: evento.id, canal: env.ANDROID_CHANNEL_ID }), contexto);
        return { d, r: resultado, diag };
      }),
    );
    // Diagnóstico por dispositivo fallido (sin token ni UID: solo su posición en la lista).
    resultados.forEach((x, i) => {
      if (x.r !== 'ok') log({ evento: 'fcm_fallo', tipo: cuerpo.tipo, dispositivo: i + 1, resultado: x.r, ...sanear(x.diag) });
    });
    const cuenta = (r) => resultados.filter((x) => x.r === r).length;
    const ok = cuenta('ok');
    const invalidos = resultados.filter((x) => x.r === 'tokenInvalido');
    const transitorios = cuenta('transitorio');
    const configuracion = cuenta('configuracion');

    // 7) Tokens que Google confirma inexistentes o inválidos: se borran del registro de su dueño.
    etapa = 'firestore_borrar_dispositivo';
    let eliminados = 0;
    for (const { d } of invalidos) {
      if (await borrarDispositivo(env, proyecto, evento.destinatarioUid, d, contexto)) eliminados++;
    }
    log({ evento: 'notify', tipo: cuerpo.tipo, dispositivos: dispositivos.length, ok, invalidos: invalidos.length, eliminados, transitorios, configuracion });

    // 8) Cierre de la deduplicación (ver dedupe.js).
    etapa = 'firestore_dedupe_cierre';
    if (ok === 0 && (transitorios > 0 || configuracion > 0)) {
      await liberar(env, proyecto, claim, contexto).catch(() => {});
      claim = null;
      return transitorios > 0
        ? error(503, 'No se pudo entregar el aviso ahora. Puedes reintentar.', { reintentable: true })
        : error(502, 'El servicio de notificaciones no pudo enviar el aviso.');
    }
    await marcarEnviado(env, proyecto, claim, contexto).catch(() => {});
    claim = null;
    return json(200, { estado: 'enviado', enviados: ok, tokensEliminados: eliminados, fallosTemporales: transitorios });
  } catch (e) {
    if (claim) await liberar(env, proyecto, claim, contexto).catch(() => {});
    // Registro de diagnóstico: SOLO valores de conjuntos cerrados (ver diagnostico.js). Nunca e.message.
    if (e instanceof RequestError) {
      log({ evento: 'notify_rechazo', http: e.status, etapa, tipo }); // el motivo ya se lo explicamos al cliente
      return error(e.status, e.message);
    }
    if (e instanceof UpstreamError) {
      log({ evento: 'notify_error', clase: 'upstream', ...sanear({ etapa, ...(e.diag ?? {}) }), ...(tipo ? { tipo } : {}) });
      return error(503, 'Servicio temporalmente no disponible. Puedes reintentar.', { reintentable: true });
    }
    if (e instanceof ConfigError) {
      // Sin mensaje: puede aludir a las credenciales. El diag solo lleva etapa, motivo y códigos permitidos.
      log({ evento: 'notify_error', clase: 'config', ...sanear({ etapa, ...(e.diag ?? {}) }), ...(tipo ? { tipo } : {}) });
      return error(500, 'El Worker no está configurado correctamente.');
    }
    log({ evento: 'notify_error', clase: 'inesperado', ...sanear({ etapa }), tipoError: nombreSeguro(e), ...(tipo ? { tipo } : {}) });
    return error(500, 'Error interno.');
  }
}

export default {
  fetch(request, env) {
    return handle(request, env);
  },
};
