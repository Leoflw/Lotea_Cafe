// Errores del Worker de limpieza. Llevan un CÓDIGO corto de una lista cerrada
// (se guarda en la cola para diagnosticar); nunca el mensaje de la excepción
// original ni credenciales.

/** Fallo que puede arreglarse solo: se reintenta con espera creciente. */
export class ErrorTemporal extends Error {
  constructor(codigo) {
    super(codigo);
    this.codigo = codigo;
  }
}

/** Falta de configuración del Worker (secreto ausente o inválido). */
export class ErrorConfig extends Error {
  constructor(codigo) {
    super(codigo);
    this.codigo = codigo;
  }
}
