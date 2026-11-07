// Validación ESTRICTA del cuerpo de POST /notify.
//
// El cliente solo puede enviar el tipo de evento y los identificadores de los
// documentos que ya existen en Firestore. Cualquier otro campo (UID o token del
// destinatario, título, texto, ruta…) se rechaza con 400: el destinatario y el
// contenido los decide el Worker, nunca el cliente.

import { RequestError } from './errores.js';

export const MAX_BODY_BYTES = 1024;
const ID = /^[A-Za-z0-9_-]{1,300}$/;

const ESQUEMAS = {
  chatMessage: ['tipo', 'connectionId', 'messageId'],
  quoteEvent: ['tipo', 'quoteId', 'eventId'],
};

export function validarCuerpo(cuerpo) {
  if (cuerpo === null || typeof cuerpo !== 'object' || Array.isArray(cuerpo)) {
    throw new RequestError(400, 'El cuerpo debe ser un objeto JSON.');
  }
  if (typeof cuerpo.tipo !== 'string' || !Object.hasOwn(ESQUEMAS, cuerpo.tipo)) {
    throw new RequestError(400, 'Tipo de evento no permitido.');
  }
  const permitidos = ESQUEMAS[cuerpo.tipo];
  const claves = Object.keys(cuerpo);
  if (claves.some((k) => !permitidos.includes(k))) {
    throw new RequestError(400, 'La petición contiene campos no permitidos.');
  }
  for (const k of permitidos) {
    if (typeof cuerpo[k] !== 'string' || !ID.test(cuerpo[k])) throw new RequestError(400, `Identificador no válido: ${k}.`);
  }
  return cuerpo.tipo === 'chatMessage'
    ? { tipo: 'chatMessage', connectionId: cuerpo.connectionId, messageId: cuerpo.messageId }
    : { tipo: 'quoteEvent', quoteId: cuerpo.quoteId, eventId: cuerpo.eventId };
}
