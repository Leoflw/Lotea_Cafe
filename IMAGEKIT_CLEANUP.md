# Limpieza segura de imágenes de ImageKit (Ronda 7, Etapa 2 + corrección de integridad)

## Política de conservación y eliminación de fotografías

| Situación | Qué pasa con la foto | Qué pasa con `loteFoto` histórico |
|---|---|---|
| **A.** Se sustituye o quita una foto y el lote **sigue existiendo** | Se pide su borrado. Si un lote o perfil **vigente** la usa → `enUso` (no se borra). Si solo la usa el **historial** (`interestRequests.loteFoto` / `quotes.loteFoto`) → **`retenida`**: no se borra y se revisa sola cada 7 días. | **No se toca.** Las solicitudes, chats y cotizaciones anteriores siguen mostrando su imagen. |
| **B.** Se **elimina el lote** | La app encola todas sus fotos. Las que solo retenía el historial se **liberan** (`retenida → pendiente`) cuando el historial ya no las usa, y se borran. | Quedan en **`null`** (solo ese campo), únicamente en las negociaciones **del vendedor** sobre **ese lote**. Lo hace el Worker; la app no puede. |

Una foto nunca se borra si **cualquiera** de estos la usa: un lote vigente, un perfil (principal o galería),
una solicitud de interés o una cotización (comparación por `fileId` y por URL; en el historial, por prefijo de URL).
Si no se puede comprobar (error de consulta, ImageKit sin URL) **no se borra** y se reintenta.

## Arquitectura
1. **App (Flutter).** Al guardar un lote o el perfil calcula qué `fileId` dejó de usarse y crea
   `users/{uid}/pendingFileDeletions/{fileId}` en el **mismo lote atómico** que guarda la foto nueva.
   `CoffeeLotRepository.eliminar` ya **no borra**: en un lote atómico deja el lote en borrador sin fotos,
   encola sus fotos y crea `users/{uid}/pendingLotDeletions/{lotId}`. Después avisa (sin esperar) al Worker.
2. **Worker `cloudflare/imagekit-cleanup`** (separado de subidas y push). Con el ID token procesa la cola
   del usuario del token (no recibe fileId ni lotId); el cron (30 min) reintenta las de todos.
   - *Eliminación de lote* (`lotes.js`): reclama con lease → comprueba `sellerId == uid` (si el lote ya no
     existe sigue) → red de seguridad: encola las fotos que la app no encoló → pone `loteFoto = null` en
     `interestRequests` y `quotes` filtrando **siempre** `coffeeLotId == lote`, `sellerId == uid` y
     `loteFoto != null` (hasta 100 por consulta; si hay más continúa en la siguiente ejecución sin gastar
     intentos) → borra el lote → libera las fotos `retenida` de ese lote → `completado`.
   - *Foto* (`cleanup.js`): reclama con lease → `GET details` (la ruta real debe estar bajo
     `{raíz}/users/{uid}/{lots|profile}` del dueño) → comprueba usos → `DELETE`.
3. **Reglas** (`firestore.rules`, **sin relajar nada de lo existente**): `interestRequests` y `quotes` siguen
   sin permitir cambios de `loteFoto` ni borrados. Nuevas: cola de fotos y cola de lotes (solo el dueño crea,
   `pendiente`, campos cerrados; la de lote exige que el lote sea suyo); un lote solo se puede borrar sin
   fotos **y** con su solicitud creada.

## Estados de la cola (nada queda sin salida)
`pendiente` → `procesando` (lease 2 min; si el proceso muere, se retoma) → `completado` | `enUso` | `retenida` |
`rechazado` | `errorTemporal` (5 min × 2ⁿ, máx. 6 h) | `fallido` (tras 6 intentos).
- `enUso`: la app puede reabrirla (`enUso → pendiente`) cuando el vendedor quita de verdad la foto.
- `retenida`: la reevalúa el Worker cada 7 días y al eliminar el lote. Si el historial deja de usarla, se borra.
- `fallido`: la app puede reabrirla (`fallido → pendiente`). Reabrir solo cambia `estado` y `createdAt`
  (lo único que permiten las reglas); al reclamarla, el Worker detecta la reapertura (`pendiente` con
  `intentos ≥ 6`), reinicia el contador y descarta `ultimoError`, `nextAttemptAt` y `motivo` del ciclo anterior.
  En la app: `PendingFileDeletions.encolar` reabre las fotos `fallido` que un guardado retira,
  `encolarBorradoDeLote` reabre la solicitud del lote y `reabrirFotosFallidas` reabre las fotos `fallido` de ese
  lote aunque el lote ya no tenga fotos; repetir `CoffeeLotRepository.eliminar` hace las tres cosas.
  `SellerRepository.guardarPerfil` hace lo mismo para el perfil: en el mismo lote atómico reabre las fotos `fallido`
  de origen `profile` y `refId` = uid (`reabrirFotosFallidas(origen: OrigenFoto.profile)`), aunque la foto ya no esté en el
  perfil, y avisa al Worker si encoló o reabrió algo. El filtro por `origen` impide reabrir solicitudes de lotes (y al
  revés). Nunca se
  reabren `completado`, `retenida`, `enUso` (salvo por `encolar`), `procesando` ni `errorTemporal`, ni solicitudes
  de otra persona (las reglas lo impiden y la app solo lee y escribe `users/{su uid}/…`).
- `rechazado`: terminal a propósito (no es del usuario o id inválido).

## Configuración (NO desplegada)
Secretos: `IMAGEKIT_PRIVATE_KEY` y `CLEANUP_SERVICE_ACCOUNT_JSON` (cuenta de servicio PROPIA). Permisos de esa
cuenta: rol personalizado con `datastore.entities.get`, `datastore.entities.list`, `datastore.entities.create`,
`datastore.entities.update` y `datastore.entities.delete`, **más `datastore.databases.get`**. Esta última la exigen
`beginTransaction` y `rollback` (documentación de IAM de Firestore) y las rutas de la etapa 6 empiezan con una transacción:
sin ella Firestore rechaza el inicio con 403 y el Worker responde `503` genérico (internamente `firestore_tx_inicio_403`, que hoy no se registra) aunque el resto funcione. `runQuery` usa `entities.get` y `entities.list`;
el commit con precondición `exists: false` usa `entities.create` y con `updateTime` usa `entities.update`.
`entities.delete` solo la necesitan las eliminaciones de lotes y de fotos (etapas 2 y 5); las rutas de cuenta no borran.
**Limitación:** IAM de Firestore no puede restringir por colección ni por campo; el código limita lo que
escribe (máscara `loteFoto`, filtro por vendedor, solo la cola y el lote solicitado), pero la cuenta *podría*
más. Variables: `FIREBASE_PROJECT_ID`, `IMAGEKIT_FOLDER_ROOT` (igual que el Worker de subidas).
**Índices** (`firestore.indexes.json`, hay que desplegarlos): compuestos `(coffeeLotId, sellerId, loteFoto)` en
`interestRequests` y `quotes`, y grupo de colección sobre `estado` en `pendingFileDeletions` y
`pendingLotDeletions`. App: `IMAGEKIT_CLEANUP_ENDPOINT` en `env.json` (opcional).

## Pruebas
- Worker (ejecutadas): `cd cloudflare/imagekit-cleanup && node --test` → 59 pruebas (incluye reapertura y un
  «contrato de estados» que compara los nombres y transiciones de la app, las reglas y el Worker).
- Reglas (NO ejecutadas aquí): `cd rules-tests && npm install && npm test` (Java + firebase-tools).
- Flutter (NO ejecutadas aquí): `flutter analyze` y `flutter test`.
- Destructivas contra ImageKit/Firestore reales: solo con proyecto Firebase y carpeta ImageKit **de pruebas**
  (`IMAGEKIT_FOLDER_ROOT = "/lotea-cafe-test"`); jamás con fotos de producción.

## Verificación en el teléfono (entorno de pruebas)
1. Compila con los endpoints de PRUEBA e instala el APK. Como comprador, solicita un café del vendedor de prueba.
2. Como vendedor, sustituye la foto principal de ese lote. En Firestore de pruebas la foto vieja debe quedar
   `retenida`, el archivo seguir en ImageKit, y la solicitud del comprador seguir mostrando su imagen.
3. Elimina el lote (la app deja `pendingLotDeletions/{lotId}`): en segundos el lote desaparece,
   `loteFoto` de la solicitud y cotización de ese lote queda en `null`, y tras una segunda ejecución la foto
   vieja se borra. Otros lotes y sus solicitudes no cambian.
4. Interrumpe el internet justo tras eliminar: la solicitud queda `pendiente` y el cron la completa.

## Eliminar un café desde «Mi catálogo» (Ronda 7, Etapa 5)

La interfaz solo **pide** la eliminación con `CoffeeLotRepository.eliminar(lote.id)` (el método de arriba);
no hay un segundo procedimiento, no borra imágenes y no toca solicitudes, cotizaciones, chats ni `loteFoto`.

- **Acción**: icono «Eliminar café» en cada fila (publicados y borradores), junto a «Editar/Completar».
- **Confirmación**: nombre del café, nº de solicitudes de interés y de cotizaciones relacionadas, y la
  explicación de que las negociaciones se conservan pero sus fotografías históricas dejarán de mostrarse.
  Cancelar no modifica nada. Al confirmar, el botón muestra un indicador y ni se repite ni se puede cerrar el
  diálogo hasta que `eliminar` responde (el error, si lo hay, se muestra dentro y se puede reintentar).
- **Contadores exactos**: `InterestRequestRepository.contarDeLote` y `QuoteRepository.contarDeLote` hacen un
  `count()` por `sellerId` + `coffeeLotId` (solo igualdades: no hace falta un índice compuesto nuevo; no se
  modificó `firestore.indexes.json`). Se reúnen en `LotDeletionImpactCounter`. Si un conteo falla, el diálogo
  dice que no pudo calcularse (con «Reintentar») y no deja confirmar: nunca muestra 0 por un error.
- **Estado pendiente**: `eliminar` deja el lote como borrador sin fotos hasta que el Worker lo borra, así que la
  app lee `users/{uid}/pendingLotDeletions` (`CoffeeLotRepository.observarEliminaciones`, reglas sin cambios) y
  distingue: `pendiente` («Eliminación pendiente»), `procesando` («Eliminando…»), `errorTemporal`
  («Eliminación en reintento», el Worker reintenta solo), `fallido` («No se pudo eliminar» + «Reintentar
  eliminación», que vuelve a llamar a `eliminar`, que reabre la solicitud) y `completado` (se oculta). Un café
  en cualquiera de esos estados no se puede abrir ni editar, no cuenta como borrador y solo aparece en «Todos».
- Las solicitudes `completado` se conservan en la cola (las reglas no permiten borrarlas).

## Eliminación de cuenta — Etapa 6 (solicitar y cancelar; NO borra nada)

Módulo `src/account-deletion.js` (+ `src/firestore-tx.js`) dentro de ESTE Worker; `index.js` solo enruta. No hay un cuarto Worker.

| Ruta | Qué hace |
|---|---|
| `POST /account-deletion/request` | Registra el periodo de espera, marca la cuenta `eliminacionPendiente` y suspende los cafés **publicados** del propio UID. |
| `POST /account-deletion/cancel` | Antes del plazo: reactiva la cuenta y restaura SOLO los cafés que suspendió esa solicitud. |
| `POST /` | Sin cambios (colas de fotos y lotes). **No** hereda el límite de `auth_time`. |

Requisitos de las rutas de cuenta: `Authorization: Bearer <ID token>`; el UID sale solo de `payload.sub`; `auth_time` de como máximo
**300 s** (la app reautentica con contraseña y pide `getIdToken(true)`); si no, `401` con `codigo: "reautenticacion"`. Límite propio de
10 llamadas / 10 min / usuario (aparte del de `POST /`). El cuerpo se ignora. Las fechas las calcula el Worker (`solicitadaAt` y
`programadaAt = solicitadaAt + RETENCION_DIAS`).

Respuestas: `200 {estado, solicitadaAt, programadaAt, retencionDias, idempotente, cafesSuspendidos}` (solicitar) ·
`200 {estado: "activa", idempotente, cafesRestaurados}` (cancelar) · `400` · `401` · `403` (sin documento de usuario) ·
`409` (estado incompatible, `plazo_vencido`, `limite_cafes`) · `429` · `503` (fallo temporal o conflicto no resuelto; no queda estado parcial).

Atomicidad: cada operación es UNA transacción REST de Firestore (`beginTransaction` → lecturas con `transaction` → `commit` con
precondiciones `updateTime`/`exists`). Con más de 498 cafés publicados se rechaza ANTES de escribir (500 escrituras por commit).

Configuración: no necesita `IMAGEKIT_PRIVATE_KEY` (solo `FIREBASE_PROJECT_ID` y `CLEANUP_SERVICE_ACCOUNT_JSON`); `POST /` sigue exigiendo lo de antes.
Variables nuevas, **públicas**, en `wrangler.toml`: `RETENCION_DIAS = "15"` y `DRY_RUN = "true"`.

`DRY_RUN` es una barrera preventiva para la etapa 7: **hoy no existe código que pueda ejecutar el borrado definitivo** (ni DELETE de
documentos, ni llamadas a ImageKit, ni cambios en Authentication), de modo que `DRY_RUN = "false"` tampoco activa nada
(`dryRunActivo` es siempre `true` mientras `BORRADO_DEFINITIVO_IMPLEMENTADO` sea `false`). No se simulan vencimientos en el Cron.
