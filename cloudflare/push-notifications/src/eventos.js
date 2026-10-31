// Verificación de que el acontecimiento es REAL y deducción del destinatario.
//
// Todas las lecturas se hacen con el ID token del propio usuario (las reglas de
// Firestore ya limitan lo que puede ver) y además se vuelven a comprobar aquí
// la pertenencia, el autor y el estado: no se confía solo en las reglas.

import { RequestError } from './errores.js';
import { leerComoUsuario, marcaMs, texto } from './firestore.js';

// Un aviso solo tiene sentido justo después de la operación. Esto impide que,
// caducado el registro de deduplicación, alguien reactive avisos antiguos.
export const EDAD_MAXIMA_MS = 15 * 60 * 1000;
const ADELANTO_MAXIMO_MS = 5 * 60 * 1000; // tolerancia de reloj

/** Quién ejecuta cada evento del historial y a quién se avisa. */
export const EVENTOS_COTIZACION = {
  solicitudCreada: { actor: 'comprador', destinatario: 'vendedor' },
  ofertaEnviada: { actor: 'vendedor', destinatario: 'comprador' },
  solicitudRechazada: { actor: 'vendedor', destinatario: 'comprador' },
  revisionSolicitada: { actor: 'comprador', destinatario: 'vendedor' },
  ofertaAceptada: { actor: 'comprador', destinatario: 'vendedor' },
  ofertaRechazada: { actor: 'comprador', destinatario: 'vendedor' },
  cancelada: { actor: 'comprador', destinatario: 'vendedor' },
};

async function leer(ctx, segmentos, queEs, objeto) {
  const r = await leerComoUsuario(ctx.proyecto, segmentos, ctx.idToken, ctx.fetchFn, objeto);
  if (r.estado === 'noEncontrado') throw new RequestError(404, `${queEs} no encontrado.`);
  if (r.estado === 'prohibido') throw new RequestError(403, `No tienes acceso a: ${queEs}.`);
  return r.doc;
}

function comprobarFrescura(doc, campo, nowMs) {
  const ms = marcaMs(doc, campo);
  if (ms === null) throw new RequestError(409, 'No se puede comprobar cuándo ocurrió el evento.');
  if (nowMs - ms > EDAD_MAXIMA_MS || ms - nowMs > ADELANTO_MAXIMO_MS) {
    throw new RequestError(409, 'El evento es demasiado antiguo para notificarlo.');
  }
}

/**
 * Mensaje de chat. Devuelve { destinatarioUid, ruta, id, clave: [tipo, a, b] }.
 * Exige: usuario participante de una conexión ACEPTADA; mensaje existente y
 * escrito por él; y que sea el último mensaje registrado en la conexión
 * (`ultimoMensajeId` y `ultimoMensajeDe`).
 */
export async function resolverChat(ctx, { connectionId, messageId }) {
  const conexion = await leer(ctx, ['interestRequests', connectionId], 'Conexión', 'conexion');
  const compradorId = texto(conexion, 'compradorId');
  const sellerId = texto(conexion, 'sellerId');
  if (ctx.uid !== compradorId && ctx.uid !== sellerId) throw new RequestError(403, 'No participas en esta conexión.');
  if (texto(conexion, 'estado') !== 'aceptada') throw new RequestError(409, 'La conexión no está aceptada.');

  const mensaje = await leer(ctx, ['chats', connectionId, 'messages', messageId], 'Mensaje', 'mensaje');
  if (texto(mensaje, 'senderId') !== ctx.uid) throw new RequestError(403, 'El mensaje no fue enviado por ti.');
  if (texto(conexion, 'ultimoMensajeId') !== messageId || texto(conexion, 'ultimoMensajeDe') !== ctx.uid) {
    throw new RequestError(409, 'Ese no es el último mensaje de la conexión.');
  }
  comprobarFrescura(mensaje, 'createdAt', ctx.nowMs);

  const destinatarioUid = ctx.uid === compradorId ? sellerId : compradorId;
  if (!destinatarioUid || destinatarioUid === ctx.uid) throw new RequestError(409, 'No hay otra persona a quien avisar.');
  return { destinatarioUid, ruta: 'chat', id: connectionId, clave: ['chatMessage', connectionId, messageId] };
}

/**
 * Evento del historial de una cotización. Exige: evento existente y de un tipo
 * permitido; `actorId` = usuario autenticado; usuario participante de la
 * cotización; y que el rol del actor (`actor`) coincida con el que corresponde
 * a ese tipo de evento. El destinatario es la otra parte.
 */
export async function resolverCotizacion(ctx, { quoteId, eventId }) {
  const cotizacion = await leer(ctx, ['quotes', quoteId], 'Cotización', 'cotizacion');
  const compradorId = texto(cotizacion, 'compradorId');
  const sellerId = texto(cotizacion, 'sellerId');
  if (ctx.uid !== compradorId && ctx.uid !== sellerId) throw new RequestError(403, 'No participas en esta cotización.');

  const evento = await leer(ctx, ['quotes', quoteId, 'events', eventId], 'Evento', 'evento');
  const tipo = texto(evento, 'tipo');
  if (tipo === null || !Object.hasOwn(EVENTOS_COTIZACION, tipo)) throw new RequestError(422, 'Tipo de evento no permitido.');
  if (texto(evento, 'actorId') !== ctx.uid) throw new RequestError(403, 'El evento no fue ejecutado por ti.');

  const def = EVENTOS_COTIZACION[tipo];
  const rolReal = ctx.uid === compradorId ? 'comprador' : 'vendedor';
  if (texto(evento, 'actor') !== rolReal || def.actor !== rolReal) throw new RequestError(403, 'El evento no corresponde a tu rol en la cotización.');
  comprobarFrescura(evento, 'fecha', ctx.nowMs);

  const destinatarioUid = def.destinatario === 'vendedor' ? sellerId : compradorId;
  if (!destinatarioUid || destinatarioUid === ctx.uid) throw new RequestError(409, 'No hay otra persona a quien avisar.');
  return { destinatarioUid, ruta: 'cotizacion', id: quoteId, clave: ['quoteEvent', quoteId, eventId] };
}
