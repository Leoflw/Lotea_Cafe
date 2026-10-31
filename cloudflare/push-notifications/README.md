# Worker de notificaciones push (FCM) — Lotea Café

Cloudflare Worker **independiente** del de ImageKit (`../imagekit-upload-auth`). Recibe
`POST /notify` desde la app, comprueba en Firestore que el mensaje o evento es real y
envía un aviso genérico por **FCM HTTP v1**. Corre en el **plan gratuito** de Workers y
no usa Cloud Functions, ni plan Blaze, ni KV/D1/Durable Objects.

## Contrato

```
POST /notify
Authorization: Bearer <ID token de Firebase Authentication>
{"tipo":"chatMessage","connectionId":"<id>","messageId":"<id>"}
{"tipo":"quoteEvent","quoteId":"<id>","eventId":"<id>"}
```

Cualquier otro campo (UID o token del destinatario, título, texto, ruta…) → **400**.

| Código | Significado |
|---|---|
| 200 `enviado` / `duplicado` / `sinDispositivos` | Procesado (idempotente: reintentar es seguro) |
| 202 `enCurso` | Otra petición está enviando ese mismo evento |
| 400 / 413 | Cuerpo mal formado, campos no permitidos, demasiado grande |
| 401 | Token de Firebase ausente, inválido, caducado, de otro proyecto o sin UID |
| 403 | No participas, el mensaje/evento no es tuyo o el rol no coincide |
| 404 / 409 / 422 | No existe / conexión no aceptada, no es el último mensaje, evento antiguo / tipo de evento no permitido |
| 429 | Más de 60 avisos en 10 min de un usuario (mejor esfuerzo, por instancia) |
| 502 / 503 / 500 | Error de configuración o de FCM / fallo temporal (reintentable) / Worker mal configurado |

## Qué verifica antes de enviar

1. **Token de Firebase** (firma RS256 con las claves públicas de Google, `aud` e `iss` del
   proyecto `lotea-cafe`, caducidad, `iat`, `auth_time`, UID válido). Copia adaptada de
   `imagekit-upload-auth/src/firebase.js`; no se importa, para que sigan independientes.
2. **Chat:** conexión `aceptada` donde participas; el mensaje existe y su `senderId` eres tú;
   es el último de la conexión (`ultimoMensajeId` y `ultimoMensajeDe`); creado hace < 15 min.
3. **Cotización:** eres participante; el evento existe, su tipo está en la lista permitida,
   `actorId` eres tú, su rol coincide con el que corresponde a ese tipo; hace < 15 min.
4. **Destinatario** = la otra parte. Se deduce de Firestore; jamás del cliente.

Las lecturas del paso 2-3 se hacen **con el ID token del propio usuario** (las reglas de
Firestore también aplican). La cuenta de servicio solo toca `users/{uid}/deviceTokens` y
`pushDedupe`.

| Evento | Lo ejecuta | Se avisa a |
|---|---|---|
| `solicitudCreada`, `revisionSolicitada`, `ofertaAceptada`, `ofertaRechazada`, `cancelada` | comprador | vendedor |
| `ofertaEnviada`, `solicitudRechazada` | vendedor | comprador |

## Deduplicación persistente (colección `pushDedupe`)

El id del documento es SHA-256 de `tipo|id1|id2`. Estados: `enviando` → `enviado`.

| Situación | Resultado |
|---|---|
| Primer envío | Se reclama el evento y se envía |
| Reintento HTTP, aunque llegue a otra instancia del Worker | `duplicado` (200), no se envía |
| Dos peticiones a la vez | Gana una; la otra recibe `duplicado` o `enCurso` (202) |
| Un intento murió a medias (> 60 s en `enviando`) | Otra petición toma el relevo (precondición por `updateTime`) |
| Destinatario sin dispositivos | No se escribe nada |

**Si FCM responde con un error:**

| Resultado del envío | Qué se hace con la deduplicación |
|---|---|
| Algún dispositivo lo recibió | Queda `enviado`: reintentar duplicaría el aviso en los que sí lo recibieron |
| Ninguno lo recibió por error **temporal** (429, 5xx, red) | Se **libera**; responde 503 `reintentable`; el reintento de la app puede enviar |
| Ninguno lo recibió por error de **configuración** (401/403, `SENDER_ID_MISMATCH`, carga inválida…) | Se **libera**; responde 502 |
| Solo había tokens inválidos | Se borran y queda `enviado` (no hay a quién reenviar) |

Límite conocido: si Firestore falla justo al marcar `enviado` tras un envío correcto, un
reintento pasado el minuto de cortesía podría duplicar un aviso. Es un caso muy raro.

Política TTL opcional: los documentos llevan `expiraEn` (7 días). En la consola de Firestore
→ *Time-to-live* puedes crear una política sobre el grupo de colecciones `pushDedupe` y el
campo `expiraEn` para que se limpien solos. El Worker solo notifica eventos de menos de
15 minutos, así que borrar antes o después no permite reactivar avisos antiguos.

## Tokens FCM inválidos

Solo se borra un registro `users/{uid}/deviceTokens/{id}` cuando Google **confirma** que el
token no existe (código FCM `UNREGISTERED`) o que `message.token` está mal formado. El
borrado lleva precondición `updateTime`: un token renovado entretanto no se pierde. **No** se
borra por 429, 5xx, errores de red, 401/403, `SENDER_ID_MISMATCH`, ni por un 404 genérico sin
`UNREGISTERED` (p. ej. un proyecto mal escrito no puede vaciar los tokens de nadie).

## Cuenta de servicio y secreto `FCM_SERVICE_ACCOUNT_JSON`

Crea una cuenta **dedicada** (p. ej. `push-notifications-worker`) en el proyecto `lotea-cafe`;
no reutilices una con rol de propietario ni la de otras herramientas.

Permisos mínimos que necesita (rol personalizado en *IAM y administración → Roles*):

- Firestore: `datastore.entities.get`, `datastore.entities.list`, `datastore.entities.create`,
  `datastore.entities.update`, `datastore.entities.delete`.
- FCM: `cloudmessaging.messages.create` (alternativa si la consola no lo ofrece en un rol
  personalizado: el rol predefinido *Firebase Cloud Messaging API Admin*).

> No pude comprobar los nombres exactos de los permisos contra la consola de Google (sin red
> en el entorno de desarrollo): confírmalos al crear el rol. IAM de Firestore **no puede**
> limitar por colección; el Worker solo toca `deviceTokens` y `pushDedupe`, pero la cuenta
> podría leer y escribir toda la base si el secreto se filtrara. Por eso el secreto vive solo
> en Cloudflare y se rota si hay dudas.

El Worker rechaza una cuenta cuyo `project_id` no sea `lotea-cafe`.

La clave privada **se introduce a mano**; nunca en el código, el ZIP, `env.json`, `.dev.vars`,
GitHub, la documentación ni el chat:

```bash
cd cloudflare/push-notifications
npx wrangler secret put FCM_SERVICE_ACCOUNT_JSON
# pega el contenido completo del JSON descargado y pulsa Enter
# (o: npx wrangler secret put FCM_SERVICE_ACCOUNT_JSON < ruta/al/archivo.json)
```

Después **borra el JSON descargado** de tu equipo.

## Límite de CPU del plan gratuito (10 ms por petición)

Lo costoso es importar la clave RSA y firmar el JWT. La clave importada y el access token se
guardan en memoria del isolate y se reutilizan hasta 5 min antes de caducar (~1 h); las
peticiones simultáneas comparten una sola renovación. No se usa la Cache API porque no
funciona en `*.workers.dev`.

**Medición local (Node, no es Cloudflare)** con `npm run medir-cpu` (incluye el coste del
Google simulado, así que sobreestima): arranque en frío ≈ 4,1 ms de mediana (máx. 6,9 ms);
isolate caliente ≈ 1,6 ms. Es una referencia, **no una prueba de que cumple en Cloudflare**.

**Compruébalo tras desplegar:**

1. Envía unos mensajes de prueba desde la app.
2. Panel de Cloudflare → Workers y Pages → `push-notifications` → *Metrics* → **CPU Time** (p50 y p99),
   y busca errores «Exceeded CPU limit» (código 1102). También: `npx wrangler tail`.
3. Fuerza arranques en frío esperando unos minutos entre envíos.

Si el p99 supera 10 ms, **antes de pagar** hay alternativas gratuitas: (a) tareas programadas
(Cron Trigger) que renueven el token cada hora y lo guarden en KV, dejando cada petición con una
lectura de KV; (b) usar un dominio propio en Cloudflare para poder compartir el token con la
Cache API; (c) reducir el trabajo por petición (p. ej. menos dispositivos por aviso). El plan
Workers de pago es la última opción.

Subpeticiones por invocación (límite gratuito: 50): como máximo ≈ 27 (claves JWKS, 2 lecturas,
lista de dispositivos, OAuth, deduplicación, ≤ 10 envíos, ≤ 10 borrados).

## Variables

| Nombre | Tipo | Valor |
|---|---|---|
| `FIREBASE_PROJECT_ID` | variable pública (`wrangler.toml`) | `lotea-cafe` |
| `ANDROID_CHANNEL_ID` | variable pública (`wrangler.toml`) | `lotea_mensajes_cotizaciones` (el canal que crea `MainActivity.kt`) |
| `FCM_SERVICE_ACCOUNT_JSON` | **secreto** | JSON de la cuenta de servicio |
| `ALLOW_HTTP` | solo `.dev.vars` local | `true` para `wrangler dev` |

## Pruebas

```bash
cd cloudflare/push-notifications
npm test          # node --test; sin red ni credenciales reales (Google simulado)
npm run medir-cpu # referencia de CPU local
```

Cubren: token ausente/inválido/de otro proyecto/caducado; cuerpo mal formado; tipos no
permitidos; intento de dictar destinatario, token o texto; mensaje inexistente, remitente
falsificado, conexión no aceptada; evento inexistente, ajeno o no permitido; destinatario de
los 7 eventos; el autor nunca recibe el aviso; deduplicación (incluida tras «reiniciar» el
Worker y en concurrencia); sin dispositivos; token inválido; errores temporales y de
configuración de Google; renovación y caché del token OAuth; y que las rutas del Worker de
ImageKit no se alteran.

## Despliegue

```bash
cd cloudflare/push-notifications
npm install
npm test
npx wrangler login
npx wrangler secret put FCM_SERVICE_ACCOUNT_JSON
npx wrangler deploy
```

`wrangler deploy` imprime la URL pública (`https://push-notifications.<tu-subdominio>.workers.dev`).
Pónla en `env.json` como `PUSH_NOTIFICATIONS_ENDPOINT` (ver `../../PUSH_NOTIFICATIONS.md`).

## Diagnóstico de fallos (registros)

Cada fallo escribe una línea JSON en `npx wrangler tail` con la **etapa**, el **servicio**
(`oauth`, `firestore`, `fcm`, `firebase_auth`), la **causa** (`red`, `http`,
`respuesta_invalida`), el **código HTTP** y, si aplica, un código de Google validado con una
lista permitida (cualquier otro valor se registra como `otro`). Nunca se registran
secretos, tokens, cabeceras, chat, identificadores de personas ni texto de las respuestas de
Google. Guía completa de lectura y despliegue: [`DIAGNOSTICO.md`](./DIAGNOSTICO.md).
Los códigos HTTP que recibe la app no cambian. Causa del 503 `causa:red` y corrección (v2): [`DIAGNOSTICO_V2.md`](./DIAGNOSTICO_V2.md).
