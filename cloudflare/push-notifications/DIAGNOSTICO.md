# Diagnóstico del Worker de notificaciones (`clase: upstream`)

Versión del Worker: v5.2 + diagnóstico v1. Solo cambia `cloudflare/push-notifications/`.
No se tocó Flutter, ImageKit, `firestore.rules` ni los repositorios comerciales, y los
códigos HTTP que recibe Flutter son los mismos de antes (503 reintentable, 500, 502…).

## 1. Qué se demuestra con el código y las pruebas

`{"evento":"notify_error","clase":"upstream"}` se escribe en un único punto
(`src/index.js`, ante un `UpstreamError`). Un `UpstreamError` se lanza en estos sitios:

| Etapa (`etapa`) | Cuándo lanza `UpstreamError` | Archivo |
|---|---|---|
| `oauth_token` | Sin red, HTTP 429/5xx, o 200 sin `access_token` | `google-auth.js` |
| `firestore_leer_evento` | Lectura **como usuario** (conexión, mensaje, cotización, evento) con HTTP distinto de 200/404/401/403, o sin red | `firestore.js` |
| `firestore_listar_dispositivos` | Lectura de `users/{uid}/deviceTokens` con **cualquier** HTTP no correcto salvo 404 (incluye 401/403/400/5xx), o sin red | `firestore.js` |
| `firestore_dedupe_crear` / `_leer` / `_relevo` | Escritura/lectura de `pushDedupe` con HTTP inesperado (crear: distinto de 409) | `dedupe.js` |
| `verificar_id_token` | Fallo al pedir las claves públicas de Firebase (antes no se registraba nada; seguía respondiendo 503) | `firebase.js` |

Consecuencias comprobadas por pruebas (`test/diagnostico.test.js`):

- **FCM no puede producir `clase: upstream`.** `enviarDetallado()` convierte sus fallos
  de red/OAuth en «transitorio» y los HTTP de FCM en un resultado clasificado; nunca lanza
  `UpstreamError`. Un fallo de FCM aparece como `evento: "fcm_fallo"` + `evento: "notify"`.
- **OAuth rechazando la cuenta** (400/401, p. ej. `invalid_grant`) es `ConfigError`
  (`clase: config`, HTTP 500), no `upstream`. Por eso, si solo ves `upstream`, el rechazo
  de credenciales por OAuth queda descartado por el código; OAuth solo da `upstream` por red,
  429/5xx o respuesta sin `access_token`.
- **401/403 en lecturas como usuario** devuelven 403 a Flutter (`notify_rechazo`), no `upstream`.

## 2. Qué NO se puede afirmar todavía

No hay forma de saber, solo con el código, cuál de las etapas de la tabla falla en tu
proyecto: el registro anterior no guardaba la etapa. Hay que desplegar y leer los nuevos
registros. En particular, que **Firebase Console entregue la prueba demuestra que el token
y FCM funcionan**, pero **no** demuestra nada sobre los permisos de la cuenta de servicio
del Worker en Firestore (la Console usa sus propias credenciales). Es una hipótesis a
comprobar con el registro, no una conclusión.

## 3. Actualizar solo este Worker y desplegar

Desde la raíz de tu proyecto (donde está la carpeta `cloudflare/`):

```bash
# 1) Copia el contenido del ZIP SOBRE la carpeta del Worker de notificaciones.
unzip -o lotea_cafe_push_diagnostico_v1.zip      # solo escribe en cloudflare/push-notifications/

# 2) Pruebas (no necesitan red ni credenciales)
cd cloudflare/push-notifications
npm install            # solo si aún no tienes node_modules (instala wrangler)
npm test               # esperado: 162 pruebas, 0 fallos

# 3) Despliegue SOLO de este Worker
npx wrangler deploy
```

- **No** hace falta volver a ejecutar `wrangler secret put FCM_SERVICE_ACCOUNT_JSON`: los
  secretos se conservan entre despliegues.
- **No** ejecutes `wrangler deploy` dentro de `cloudflare/imagekit-upload-auth`: no cambió.
- No hay que publicar reglas de Firestore ni recompilar la app.

## 4. Observar los nuevos registros

En una terminal (dentro de `cloudflare/push-notifications`):

```bash
npx wrangler tail --format json
# solo los errores:
npx wrangler tail --format json --search notify_error
```

Provoca una notificación desde la app (envía un mensaje de chat al otro usuario) y busca
estas líneas:

```json
{"evento":"notify_error","clase":"upstream","etapa":"firestore_listar_dispositivos","servicio":"firestore","causa":"http","http":403,"googleStatus":"PERMISSION_DENIED","tipo":"chatMessage"}
{"evento":"fcm_fallo","tipo":"chatMessage","dispositivo":1,"resultado":"transitorio","etapa":"fcm_enviar","servicio":"fcm","causa":"http","http":503,"googleStatus":"UNAVAILABLE"}
{"evento":"notify","tipo":"chatMessage","dispositivos":1,"ok":1,"invalidos":0,"eliminados":0,"transitorios":0,"configuracion":0}
```

(Son ejemplos del formato, no resultados reales de tu proyecto.)

### Campos

| Campo | Valores posibles |
|---|---|
| `evento` | `notify_error`, `notify_rechazo` (4xx de la petición), `fcm_fallo` (un dispositivo), `notify` (resumen) |
| `clase` | `upstream` (503), `config` (500), `inesperado` (500) |
| `etapa` | `verificar_id_token`, `firestore_leer_evento`, `oauth_cuenta_servicio`, `oauth_token`, `firestore_listar_dispositivos`, `firestore_dedupe_crear/_leer/_relevo`, `fcm_enviar`, … |
| `operacion` | Etapa que pidió el token OAuth (p. ej. `firestore_listar_dispositivos`) cuando el fallo fue de OAuth |
| `servicio` / `causa` | `oauth`/`firestore`/`fcm`/`firebase_auth` · `red`/`http`/`respuesta_invalida` |
| `http` | Código HTTP de Google |
| `googleStatus`, `googleRazon`, `fcmCodigo`, `oauthError` | Código de Google **de lista permitida**, o `otro` si no está en la lista |
| `objeto` | `conexion`/`mensaje`/`cotizacion`/`evento` (lectura como usuario) |
| `motivo` | Problema local del secreto (`json_invalido`, `sin_clave_privada`, `proyecto_distinto`, …) o `oauth_rechazado` |
| `tipoError` | Solo en `inesperado`: nombre de la clase del error (`SyntaxError`, `TypeError`…) |
| `errorNombre`, `errorCodigo` | (v2) Solo si `causa` es `red`: clase de la excepción (`TypeError`, `DOMException`…) y código técnico de una lista cerrada. Ver `DIAGNOSTICO_V2.md` |

### Qué información adicional dará (y cómo usarla)

- **`etapa` + `http` + `googleStatus`/`googleRazon`** señalan la llamada exacta que falla. Por
  ejemplo, un `PERMISSION_DENIED` en `firestore_listar_dispositivos` o `firestore_dedupe_*`
  apuntaría a permisos de la cuenta de servicio sobre Firestore (o a la API de Firestore
  deshabilitada si `googleRazon` es `SERVICE_DISABLED`); un `oauth_token` con
  `oauthError: invalid_grant` apuntaría a una clave revocada o mal copiada. Son pistas para
  verificar en la consola de Google Cloud, no una causa demostrada.
- **`operacion`** distingue si OAuth falló al listar dispositivos, al deduplicar o al enviar.
- **`fcm_fallo`** dice qué respondió FCM por dispositivo (`resultado`, `http`, `fcmCodigo`).
- Si aparece `notify` con `ok: 1` y la notificación no llega, el Worker y FCM funcionaron y el
  problema estaría en el dispositivo o en cómo la app presenta el aviso.
- Si tras desplegar no aparece ninguna línea nueva, comprueba que el despliegue terminó
  (`npx wrangler deployments list`) y que el `tail` apunta al Worker `push-notifications`.

Si me pegas 2-3 líneas del `tail` (son seguras: no contienen secretos), se puede acotar la
causa con datos reales.

## 5. Garantía de privacidad

Los registros solo contienen valores de conjuntos cerrados y números HTTP
(`src/diagnostico.js`, función `sanear`, última barrera antes de escribir). No incluyen
`FCM_SERVICE_ACCOUNT_JSON`, claves, JWT, access tokens, tokens FCM, cabeceras
`Authorization`, contenido del chat, UID, identificadores de conexión/mensaje ni el texto de
las respuestas de Google. Las pruebas lo verifican con respuestas de Google «hostiles» en
cada etapa y con mutaciones deliberadas (registrar `e.message` o el token hace fallar la
suite).
