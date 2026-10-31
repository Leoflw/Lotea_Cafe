// Errores tipados del Worker. Cada uno se traduce a un código HTTP en index.js.
//
// UpstreamError y ConfigError pueden llevar un `diag`: un objeto con datos de
// DIAGNÓSTICO ya reducidos a valores seguros (etapa, servicio, código HTTP y
// códigos de Google validados con listas permitidas; ver diagnostico.js). Nunca
// contiene mensajes, cuerpos de respuesta, tokens ni credenciales. El mensaje
// del error y el diag NO se devuelven al cliente: solo se usan para el registro.

/** Fallo atribuible a la petición (4xx). El mensaje es seguro para el cliente. */
export class RequestError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Google (Firestore, OAuth o FCM) no respondió bien de forma temporal (503). */
export class UpstreamError extends Error {
  constructor(message, diag = null) {
    super(message);
    this.diag = diag;
  }
}

/** Configuración o credenciales del Worker incorrectas (500/502). */
export class ConfigError extends Error {
  constructor(message, diag = null) {
    super(message);
    this.diag = diag;
  }
}
