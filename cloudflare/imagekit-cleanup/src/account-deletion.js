// Ciclo de vida de la eliminación de cuenta — ETAPA 6: SOLICITAR y CANCELAR. NO borra nada.
//
// Rutas (las enruta index.js; el UID sale SOLO del ID token verificado):
//   POST /account-deletion/request   registra el periodo de espera y suspende los cafés publicados
//   POST /account-deletion/cancel    cancela antes del plazo y restaura SOLO lo que suspendió esa solicitud
//
// Cada operación es UNA transacción de Firestore (firestore-tx.js): lee el usuario, el trabajo y los
// cafés afectados, y confirma de forma atómica con precondiciones. Si algo cambia mientras tanto se
// relee y se reintenta; si no se resuelve, 503 y NO queda ningún estado parcial.
//
// Documentos que escribe SOLO este Worker (cuenta de servicio, fuera de las reglas del cliente):
//   accountDeletionJobs/{uid}: estado, solicitudId, solicitadaAt, programadaAt, retencionDias, updatedAt, canceladaAt
//   users/{uid}:               cuentaEstado, eliminacionSolicitadaAt, eliminacionProgramadaAt
//   coffeeLots/{id} (solo los publicados del propio UID): estado, estadoPrevio, suspensionSolicitudId
// Nada más: ni fotos, ni perfiles, ni solicitudes, cotizaciones o chats.
//
// LÍMITE DE LA ETAPA 6: este módulo no contiene ninguna operación destructiva (ni DELETE de documentos,
// ni llamadas a ImageKit, ni cambios en Firebase Authentication). `DRY_RUN` es una barrera preventiva
// para la etapa 7: mientras BORRADO_DEFINITIVO_IMPLEMENTADO sea false, `dryRunActivo` es siempre true
// aunque la variable diga «false».

import { ErrorConfig, ErrorTemporal } from './errores.js';
import { AuthError, ReauthError, verifyIdToken } from './firebase.js';
import { marcaMs, nombreDoc, texto, vEntero, vNulo, vTexto, vTiempo } from './firestore.js';
import { abandonar, comenzar, confirmarTx, consultarEnTx, filtroIgual, leerEnTx, unirY, ConflictoTransaccion } from './firestore-tx.js';

export const COLECCION_TRABAJOS = 'accountDeletionJobs';
export const MAX_ANTIGUEDAD_AUTH_S = 300; // auth_time máximo (5 min) SOLO en estas rutas
export const RETENCION_POR_DEFECTO = 15;
export const MAX_ESCRITURAS = 500; // límite de Firestore por commit
export const MAX_CAFES = MAX_ESCRITURAS - 2; // + trabajo + usuario
export const MAX_INTENTOS_TX = 3;
const DIA_MS = 24 * 60 * 60 * 1000;
const LIMITE = { max: 10, ventanaMs: 10 * 60 * 1000 }; // 10 llamadas / 10 min / usuario (propio de estas rutas)

/** Etapa 6: no existe código de borrado definitivo. La etapa 7 lo cambiará con autorización expresa. */
export const BORRADO_DEFINITIVO_IMPLEMENTADO = false;
export function dryRunActivo(env) {
  return BORRADO_DEFINITIVO_IMPLEMENTADO ? env.DRY_RUN !== 'false' : true;
}

/** Error con respuesta HTTP propia (mensaje en español y código corto, sin datos de nadie). */
export class ErrorCuenta extends Error {
  constructor(estado, codigo, mensaje) {
    super(codigo);
    this.estado = estado;
    this.codigo = codigo;
    this.mensaje = mensaje;
  }
}

/** Días de espera: `RETENCION_DIAS` (entero 1–365); sin definir vale 15. Un valor inválido es error de configuración. */
export function retencionDias(env) {
  const crudo = env.RETENCION_DIAS;
  if (crudo === undefined || crudo === null || String(crudo).trim() === '') return RETENCION_POR_DEFECTO;
  const n = Number(crudo);
  if (!Number.isInteger(n) || n < 1 || n > 365) throw new ErrorConfig('retencion_invalida');
  return n;
}

export function configuradoCuentas(env) {
  return Boolean(env.FIREBASE_PROJECT_ID && env.CLEANUP_SERVICE_ACCOUNT_JSON);
}

// ---- límite de llamadas (independiente del de POST /) ----
const usos = new Map();
export function resetLimitadorCuentas() {
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

const json = (estado, cuerpo) =>
  new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
const fallo = (estado, mensaje, codigo) => json(estado, { error: mensaje, ...(codigo ? { codigo } : {}) });

const iso = (doc, campo) => doc?.fields?.[campo]?.timestampValue ?? null;
const cuentaDe = (user) => texto(user, 'cuentaEstado') ?? 'activa'; // ausente = activa (usuarios antiguos)
const rutaCafe = (doc) => String(doc.name).split('/').slice(-2).join('/');
const esCafeDe = (doc, uid) => rutaCafe(doc).startsWith('coffeeLots/') && texto(doc, 'sellerId') === uid;

function cuerpoPendiente(job, idempotente) {
  return {
    estado: 'eliminacionPendiente',
    solicitadaAt: iso(job, 'solicitadaAt'),
    programadaAt: iso(job, 'programadaAt'),
    retencionDias: Number(job.fields?.retencionDias?.integerValue ?? RETENCION_POR_DEFECTO),
    idempotente,
  };
}

const ESTADO_INCOMPATIBLE = () => new ErrorCuenta(409, 'estado_incompatible', 'No se puede procesar la solicitud en el estado actual de tu cuenta.');
const SIN_CUENTA = () => new ErrorCuenta(403, 'cuenta_no_autorizada', 'Esta cuenta no puede realizar la operación.');

// ---------------------------------------------------------------------------------------------
// Solicitar
// ---------------------------------------------------------------------------------------------

async function solicitarEnTx(env, uid, tx, deps) {
  const dias = retencionDias(env);
  const proyecto = env.FIREBASE_PROJECT_ID;
  const user = await leerEnTx(env, tx, ['users', uid], deps);
  if (!user) throw SIN_CUENTA();
  const cuenta = cuentaDe(user);
  const job = await leerEnTx(env, tx, [COLECCION_TRABAJOS, uid], deps);
  const jobPendiente = job !== null && texto(job, 'estado') === 'pendiente';

  if (cuenta === 'eliminacionPendiente') {
    // Idempotente: misma solicitud vigente, misma fecha original, sin escribir nada.
    if (jobPendiente) return { cuerpo: cuerpoPendiente(job, true), sinEscritura: true };
    throw ESTADO_INCOMPATIBLE();
  }
  if (cuenta !== 'activa' || jobPendiente) throw ESTADO_INCOMPATIBLE(); // «eliminando», estados futuros o datos incoherentes

  const candidatos = await consultarEnTx(
    env, tx, 'coffeeLots', unirY([filtroIgual('sellerId', uid), filtroIgual('estado', 'publicado')]), MAX_CAFES + 1, deps,
  );
  if (candidatos.length > MAX_CAFES) {
    throw new ErrorCuenta(409, 'limite_cafes', 'Tienes demasiados cafés publicados para procesar la solicitud de una sola vez. Despublica o elimina algunos e inténtalo de nuevo.');
  }
  const cafes = candidatos.filter((c) => esCafeDe(c, uid) && texto(c, 'estado') === 'publicado');

  const solicitadaMs = deps.nowMs; // reloj del Worker, nunca el del teléfono
  const programadaMs = solicitadaMs + dias * DIA_MS;
  const solicitudId = (deps.idFn ?? (() => crypto.randomUUID()))();

  const writes = [
    {
      update: {
        name: nombreDoc(proyecto, COLECCION_TRABAJOS, uid),
        fields: {
          estado: vTexto('pendiente'),
          solicitudId: vTexto(solicitudId),
          solicitadaAt: vTiempo(solicitadaMs),
          programadaAt: vTiempo(programadaMs),
          retencionDias: vEntero(dias),
          updatedAt: vTiempo(solicitadaMs),
        },
      },
      currentDocument: job ? { updateTime: job.updateTime } : { exists: false },
    },
    {
      update: {
        name: nombreDoc(proyecto, 'users', uid),
        fields: {
          cuentaEstado: vTexto('eliminacionPendiente'),
          eliminacionSolicitadaAt: vTiempo(solicitadaMs),
          eliminacionProgramadaAt: vTiempo(programadaMs),
        },
      },
      updateMask: { fieldPaths: ['cuentaEstado', 'eliminacionSolicitadaAt', 'eliminacionProgramadaAt'] },
      currentDocument: { updateTime: user.updateTime },
    },
    ...cafes.map((c) => ({
      update: {
        name: c.name,
        fields: { estado: vTexto('suspendido'), estadoPrevio: vTexto('publicado'), suspensionSolicitudId: vTexto(solicitudId) },
      },
      updateMask: { fieldPaths: ['estado', 'estadoPrevio', 'suspensionSolicitudId'] },
      currentDocument: { updateTime: c.updateTime },
    })),
  ];
  await confirmarTx(env, tx, writes, deps);
  return {
    cuerpo: {
      estado: 'eliminacionPendiente',
      solicitadaAt: new Date(solicitadaMs).toISOString(),
      programadaAt: new Date(programadaMs).toISOString(),
      retencionDias: dias,
      idempotente: false,
      cafesSuspendidos: cafes.length,
    },
    sinEscritura: false,
  };
}

// ---------------------------------------------------------------------------------------------
// Cancelar
// ---------------------------------------------------------------------------------------------

async function cancelarEnTx(env, uid, tx, deps) {
  const proyecto = env.FIREBASE_PROJECT_ID;
  const user = await leerEnTx(env, tx, ['users', uid], deps);
  if (!user) throw SIN_CUENTA();
  const cuenta = cuentaDe(user);
  const job = await leerEnTx(env, tx, [COLECCION_TRABAJOS, uid], deps);
  const jobPendiente = job !== null && texto(job, 'estado') === 'pendiente';

  if (cuenta === 'activa') {
    if (jobPendiente) throw ESTADO_INCOMPATIBLE(); // cuenta activa con trabajo vigente: incoherente, no se toca
    // Nada que cancelar (ya cancelada o nunca solicitada): idempotente.
    return { cuerpo: { estado: 'activa', idempotente: true, cafesRestaurados: 0 }, sinEscritura: true };
  }
  if (cuenta !== 'eliminacionPendiente' || !jobPendiente) throw ESTADO_INCOMPATIBLE();

  const programadaMs = marcaMs(job, 'programadaAt');
  const solicitudId = texto(job, 'solicitudId');
  if (programadaMs === null || !solicitudId) throw ESTADO_INCOMPATIBLE();
  if (deps.nowMs >= programadaMs) {
    throw new ErrorCuenta(409, 'plazo_vencido', 'El plazo para cancelar la solicitud ya terminó.');
  }

  const candidatos = await consultarEnTx(
    env, tx, 'coffeeLots', unirY([filtroIgual('suspensionSolicitudId', solicitudId), filtroIgual('estado', 'suspendido')]), MAX_CAFES + 1, deps,
  );
  if (candidatos.length > MAX_CAFES) throw ESTADO_INCOMPATIBLE();
  // Solo los de ESTE vendedor, suspendidos por ESTA solicitud, que siguen suspendidos y venían publicados.
  const cafes = candidatos.filter(
    (c) => esCafeDe(c, uid) && texto(c, 'estado') === 'suspendido' && texto(c, 'suspensionSolicitudId') === solicitudId && texto(c, 'estadoPrevio') === 'publicado',
  );

  const ahora = deps.nowMs;
  const writes = [
    {
      update: {
        name: nombreDoc(proyecto, COLECCION_TRABAJOS, uid),
        fields: { estado: vTexto('cancelado'), canceladaAt: vTiempo(ahora), updatedAt: vTiempo(ahora) },
      },
      updateMask: { fieldPaths: ['estado', 'canceladaAt', 'updatedAt'] },
      currentDocument: { updateTime: job.updateTime },
    },
    {
      update: {
        name: nombreDoc(proyecto, 'users', uid),
        fields: { cuentaEstado: vTexto('activa'), eliminacionSolicitadaAt: vNulo(), eliminacionProgramadaAt: vNulo() },
      },
      updateMask: { fieldPaths: ['cuentaEstado', 'eliminacionSolicitadaAt', 'eliminacionProgramadaAt'] },
      currentDocument: { updateTime: user.updateTime },
    },
    ...cafes.map((c) => ({
      // `estado` vuelve a su valor previo; `estadoPrevio` y `suspensionSolicitudId` se eliminan (están en la máscara y no en `fields`).
      update: { name: c.name, fields: { estado: vTexto('publicado') } },
      updateMask: { fieldPaths: ['estado', 'estadoPrevio', 'suspensionSolicitudId'] },
      currentDocument: { updateTime: c.updateTime },
    })),
  ];
  await confirmarTx(env, tx, writes, deps);
  return { cuerpo: { estado: 'activa', idempotente: false, cafesRestaurados: cafes.length }, sinEscritura: false };
}

async function enTransaccion(env, uid, deps, operacion) {
  for (let intento = 0; intento < MAX_INTENTOS_TX; intento++) {
    const tx = await comenzar(env, deps);
    try {
      const r = await operacion(env, uid, tx, deps);
      if (r.sinEscritura) await abandonar(env, tx, deps);
      return r.cuerpo;
    } catch (e) {
      if (e instanceof ConflictoTransaccion) continue; // el commit fallido ya cerró la transacción: se relee todo
      await abandonar(env, tx, deps);
      throw e;
    }
  }
  throw new ErrorTemporal('firestore_conflicto');
}

export const solicitar = (env, uid, deps) => enTransaccion(env, uid, deps, solicitarEnTx);
export const cancelar = (env, uid, deps) => enTransaccion(env, uid, deps, cancelarEnTx);

// ---------------------------------------------------------------------------------------------
// Entrada HTTP (autenticación, antigüedad de la sesión, límite de llamadas, errores)
// ---------------------------------------------------------------------------------------------

export async function manejarCuenta(request, env, deps, accion) {
  if (!configuradoCuentas(env)) return fallo(500, 'El Worker no está configurado.');
  const m = /^Bearer (.+)$/.exec(request.headers.get('Authorization') || '');
  if (!m) return fallo(401, 'Falta el token de sesión.', 'sesion');
  let payload;
  try {
    payload = await verifyIdToken(m[1].trim(), {
      projectId: env.FIREBASE_PROJECT_ID, fetchFn: deps.fetchFn, nowMs: deps.nowMs, maxAuthAgeSeconds: MAX_ANTIGUEDAD_AUTH_S,
    });
  } catch (e) {
    if (e instanceof ReauthError) return fallo(401, 'Por seguridad, confirma de nuevo tu contraseña para continuar.', 'reautenticacion');
    if (e instanceof AuthError) return fallo(401, 'Sesión no válida. Inicia sesión de nuevo.', 'sesion');
    return fallo(503, 'No se pudo validar la sesión. Inténtalo de nuevo.', 'temporal');
  }
  const uid = payload.sub; // solo del token verificado; el cuerpo, la query y las cabeceras se ignoran
  if (excedeLimite(uid, deps.nowMs)) return fallo(429, 'Demasiadas llamadas seguidas. Espera unos minutos.', 'limite');
  try {
    return json(200, await (accion === 'cancelar' ? cancelar : solicitar)(env, uid, deps));
  } catch (e) {
    if (e instanceof ErrorCuenta) return fallo(e.estado, e.mensaje, e.codigo);
    if (e instanceof ErrorConfig) return fallo(500, 'El Worker no está configurado correctamente.');
    return fallo(503, 'No se pudo completar la operación ahora. Inténtalo de nuevo en unos minutos.', 'temporal');
  }
}
