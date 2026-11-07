# Informe v5.2 — pruebas de reglas de Firestore (emulador)

## Estado honesto de la validación

**No pude ejecutar la suite del emulador en este entorno**: no hay `firebase-tools`, ni
`@firebase/rules-unit-testing`, ni acceso a red para instalarlos. Por tanto **no afirmo que las
21 pruebas pasen**. Lo único que ejecuté realmente fue `node --check` sobre los dos archivos de
prueba (sintaxis correcta). La validación definitiva es el comando combinado en tu PC.

## Cambios

| Archivo | Cambio |
|---|---|
| `rules-tests/device_tokens.rules.test.js` | `beforeEach` usa **un solo** `ctx.firestore()`; `projectId` propio |
| `rules-tests/chat_state.rules.test.js` | solo `projectId` propio |
| `rules-tests/package.json` | el script `npm test` añade `--test-concurrency=1` (defensa extra) |

`firestore.rules` **no se modificó**: ninguna garantía de seguridad se debilitó y no se tocó
ninguna prueba negativa. Tampoco se tocó Flutter, ImageKit, el Worker de notificaciones ni los
repositorios.

## Problema 2 (deviceTokens) — causa raíz (alta confianza)

El `beforeEach` llamaba a `ctx.firestore()` **dos veces sobre el mismo contexto** (una por cada
`setDoc` de la siembra). El primer `setDoc` inicia el cliente; la segunda llamada reaplica la
configuración del emulador a un Firestore ya iniciado y lanza «Firestore has already been
started…». Como falla en el hook, **fallan las 8 pruebas del archivo**, también la primera, que
no hace nada raro. En `chat_state` la siembra guarda el cliente en `const db` y por eso no falla.
Corrección: un único `const db = ctx.firestore()` por contexto. El resto de las pruebas ya crea
un contexto nuevo por llamada a `dbDe(uid)` y usa un cliente por contexto.

## Problema 1 (envío legítimo del chat) — causa raíz (probable, no verificada en emulador)

Tracé las reglas para el lote «crear mensaje + actualizar último mensaje» y **la lógica es
correcta**: `resource.data.estado == 'aceptada'`; el campo `touchesOnly` coincide; `exists()`
(antes) es falso y `existsAfter()`/`getAfter()` (después) son verdaderos; `senderId == uid()`;
`createdAt`, `ultimoMensajeAt` y `request.time` son la misma hora del servidor dentro del lote;
`ultimoMensajeDe == uid()`. Son 3 accesos a documentos, muy por debajo del límite.

Indicios de que el fallo no está en las reglas:

- «Null value error» en L312 (`get()` de la conexión) y en L275 (`resource.data`) significa que
  `interestRequests/buyer1_lot1` **no existía** en ese instante. Con la conexión sembrada, el
  mismo camino pasa.
- En tu ejecución pasó «el vendedor también puede enviar», que recorre exactamente el mismo
  camino de reglas. Solo falló la **primera** prueba del archivo.
- Los dos archivos se ejecutan **en paralelo** con `node --test a b`, comparten emulador y
  usaban el mismo `projectId`. El `beforeEach` de `device_tokens` fallaba tras llamar a
  `clearFirestore()` 8 veces seguidas, y ese borrado (sobre todo el proyecto) coincidió con la
  primera prueba del chat y le quitó la conexión sembrada.

Corrección: cada archivo usa su propio `projectId` (`lotea-cafe-test-chat-state` y
`lotea-cafe-test-device-tokens`), así `clearFirestore()` de uno ya no afecta al otro, aunque
corran a la vez y sin cambiar tu comando. Cada `initializeTestEnvironment` carga las reglas de
`firestore.rules` para su proyecto, así que siguen probándose las reglas reales.

Si tras esto la prueba legítima siguiera fallando de forma aislada, pega el registro del
emulador: entonces la causa sí estaría en las reglas y habría que revisarlas con ese dato.

## Qué debes ejecutar en tu PC

1. Legítima sola: `firebase emulators:exec --config firebase.json --only firestore --project lotea-cafe-test "node --test --test-name-pattern='envío legítimo' rules-tests/chat_state.rules.test.js"`
2. Las 13 del chat: `... "node --test rules-tests/chat_state.rules.test.js"`
3. Las 8 de tokens: `... "node --test rules-tests/device_tokens.rules.test.js"`
4. Combinada: `firebase emulators:exec --config firebase.json --only firestore --project lotea-cafe-test "node --test rules-tests/chat_state.rules.test.js rules-tests/device_tokens.rules.test.js"`

Ninguna de las cuatro fue ejecutada por mí. No se publicaron reglas ni se hicieron cambios remotos.
