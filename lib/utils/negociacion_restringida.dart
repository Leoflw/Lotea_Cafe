import 'package:firebase_core/firebase_core.dart';
import '../repositories/repo_exception.dart';

/// Textos y criterio para cuando Firestore rechaza una acción comercial porque la OTRA parte
/// tiene la cuenta restringida (p. ej. periodo de espera de una eliminación de cuenta).
///
/// La app no puede leer el estado de la cuenta de la contraparte (las reglas lo impiden a
/// propósito), así que solo se entera cuando el servidor rechaza la acción. Por eso los textos
/// hablan de «una restricción temporal en una de las cuentas»: no afirman cuál ni por qué, y no
/// revelan a la contraparte que existe una solicitud de eliminación.

/// `true` si [error] es un rechazo de permisos que vino de Firestore (no un chequeo local como
/// «No participas en esta cotización»).
bool esRechazoPorPermisos(Object error) =>
    error is RepoException && error.tipo == RepoErrorKind.sinPermisos && error.causa is FirebaseException;

const tituloModoConsulta = 'Modo de consulta';

/// Texto fijo del aviso del chat (también sustituye al campo de escritura).
const mensajeChatSoloConsulta =
    'Puedes leer los mensajes anteriores, pero por ahora no es posible enviar mensajes nuevos. '
    'Puede deberse a una restricción temporal en una de las cuentas. Tu historial se conserva.';

/// Aviso PERMANENTE del chat cuando la otra persona eliminó su cuenta (no es una restricción temporal:
/// no se ofrece «Volver a intentar»). El campo de escritura queda deshabilitado.
const mensajeChatContraparteEliminada =
    'Esta cuenta fue eliminada. La conversación se conserva únicamente como historial.';

/// Aviso de una cotización: [intento] va en infinitivo («aceptar la oferta»).
String mensajeNegociacionRestringida(String intento) =>
    'No se pudo $intento. Esta negociación está temporalmente en modo de consulta: '
    'puedes revisar su historial, pero por ahora no es posible realizar acciones nuevas. '
    'Puede deberse a una restricción temporal en una de las cuentas.';

/// Aviso fijo de los formularios (enviar oferta, solicitar cotización) en modo de consulta.
const mensajeFormularioSoloConsulta =
    'Esta operación no está disponible por una restricción temporal en una de las cuentas.';

/// Texto fijo dentro de la cotización cuando está en modo de consulta.
const mensajeCotizacionSoloConsulta =
    'Puedes revisar el historial de esta cotización, pero por ahora no es posible realizar acciones nuevas. '
    'Puede deberse a una restricción temporal en una de las cuentas.';
