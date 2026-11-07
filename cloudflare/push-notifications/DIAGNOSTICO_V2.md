# Diagnóstico v2 — causa del 503 `etapa: firestore_listar_dispositivos, causa: red`

Solo cambia `cloudflare/push-notifications/`. No se tocó IAM, reglas de Firestore, la cuenta de
servicio ni su clave, Flutter ni ImageKit. Autenticación, autorización y deduplicación siguen igual.

## 1. Causa encontrada

**Defecto de implementación en `src/google-auth.js`, función `fetchConCuenta()`**: llamaba al `fetch`
global como método de un objeto:

```js
return await deps.fetchFn(url, { ... });   // v1: `this` = deps, no el global
```

En Cloudflare Workers, `fetch` llamado con un `this` ajeno lanza
`TypeError: Illegal invocation: function called with incorrect 'this' reference`
(documentado en developers.cloudflare.com/workers/observability/errors, sección «Illegal invocation»;
varios SDK lo corrigieron con `fetch.bind(globalThis)`).

Por qué encaja con lo observado, punto por punto:

| Observación | Explicación |
|---|---|
| Flutter llega al Worker y la sesión se valida | `verifyIdToken` llama a `fetchFn(...)` como función simple |
| No hay error `oauth_token` | `pedirAccessToken` también llama a `fetchFn(...)` como función simple |
| La lectura del mensaje/conexión como usuario funciona | `leerComoUsuario` igual: llamada simple |
| Falla **la primera llamada con cuenta de servicio**: `firestore_listar_dispositivos`, `causa: red` | Es la primera que pasa por `deps.fetchFn(...)`; la excepción cae en el `catch` de transporte (v1 registraba «red» sin más) |
| Sin `http` ni `googleStatus` en el registro | No hubo respuesta HTTP: Firestore ni siquiera recibió la petición |
| Firebase Console funciona; IAM/API/token correctos | Es coherente: el fallo ocurre **antes** de salir a Internet, así que ningún permiso influye |

La URL REST y la petición están bien formadas (`GET https://firestore.googleapis.com/v1/projects/lotea-cafe/databases/(default)/documents/users/{uid}/deviceTokens?pageSize=20`,
cabecera `Authorization: Bearer <access token>`, sin cuerpo); una prueba fija la URL exacta.
También afectaba a la deduplicación y al envío a FCM, que usan la misma función: habrían fallado igual.

### Qué está demostrado y qué no

- **Demostrado** (código + pruebas): `google-auth.js:158` era la única llamada a `fetch` hecha como
  método; todas las demás eran simples. Con un `fetch` que emula la comprobación de `this` de
  Workers, las pruebas de regresión **fallan con el código v1 y pasan con v2**.
- **No ejecutado aquí**: el runtime real de Workers (no hay red ni `wrangler` en este entorno). El
  emulador de las pruebas reproduce el comportamiento *documentado*, no es workerd.
- **Confirmación que falta**: tras desplegar, ver en `wrangler tail` un `notify` con `ok:1` y la
  notificación en el teléfono. Si la causa fuera otra, v2 la mostrará con `errorNombre`/`errorCodigo`.

## 2. Qué cambió

1. **Corrección:** `fetchConCuenta` extrae `const { fetchFn } = deps` y lo llama como función simple.
   Además, `index.js` envuelve el `fetch` global (`(a, b) => fetch(a, b)`) para que nunca se invoque
   con un `this` ajeno.
2. **Captura segura de excepciones de transporte** (`diagnostico.js`, `clasificarExcepcion`): se
   registra `errorNombre` (clase: `TypeError`, `DOMException`, `Error`…, o `otro`) y `errorCodigo`
   (lista cerrada: `invocacion_ilegal`, `conexion_perdida`, `limite_subpeticiones`, `timeout`,
   `abortado`, `cuerpo_ya_usado`, códigos de sistema como `ECONNRESET`, o `sin_clasificar`).
   El mensaje del error solo se usa para elegir el código; **nunca se copia al registro**.
   Aplica a OAuth, Firestore (usuario y cuenta), claves de Firebase, deduplicación y FCM.
3. **Excepción vs. respuesta HTTP:** una excepción da `causa:"red"` + `errorNombre/errorCodigo` (sin
   `http`); una respuesta 401/403/429/5xx da `causa:"http"` + `http` + `googleStatus` (sin clase).
   Ante un 401 se renueva el token una vez y se reintenta (como antes).
4. **Comprobación de conectividad opcional** `GET /diagnostico` (sección 4).

## 3. Desplegar solo el Worker de notificaciones

```bash
# Desde la raíz del proyecto: copia el ZIP sobre la carpeta del Worker
unzip -o lotea_cafe_push_diagnostico_v2.zip     # solo escribe en cloudflare/push-notifications/

cd cloudflare/push-notifications
npm install            # solo si falta node_modules
npm test               # esperado: 162 pruebas, 0 fallos
npx wrangler deploy    # TÚ lo ejecutas; nada se despliega automáticamente
```

No hace falta repetir `wrangler secret put FCM_SERVICE_ACCOUNT_JSON`. No despliegues
`cloudflare/imagekit-upload-auth`. No hay que tocar reglas ni recompilar la app.

## 4. Verificar la corrección

**A. Con la app (prueba real).** En una terminal:

```bash
npx wrangler tail --format json
```

Anota que el `deploy` muestre una versión **distinta** de `f74a3e9a-9598-4150-8a46-68f4b35a733e`.
Envía un mensaje **nuevo** de chat (un evento de más de 15 minutos se rechaza con 409, así que no
reutilices el anterior). Esperado:

```json
{"evento":"notify","tipo":"chatMessage","dispositivos":1,"ok":1,"invalidos":0,"eliminados":0,"transitorios":0,"configuracion":0}
```

sin `notify_error`, con HTTP 200 hacia Flutter y la notificación en el teléfono.

**B. Comprobación autenticada desde el Worker (opcional, sin app).** Es de solo lectura, usa un
documento fijo inexistente (`pushDedupe/diagnostico-conectividad`) y no toca datos de usuarios ni
envía FCM. Está **desactivada** salvo que exista el secreto `DIAGNOSTICO_TOKEN`:

```bash
node -e "console.log(require('crypto').randomBytes(24).toString('hex'))"   # genera un token (48 hex)
npx wrangler secret put DIAGNOSTICO_TOKEN                                  # pega ese token (puede crear una versión nueva)
curl -H "Authorization: Bearer <TOKEN>" https://push-notifications.lotea-cafe.workers.dev/diagnostico
# PowerShell: Invoke-RestMethod -Uri https://push-notifications.lotea-cafe.workers.dev/diagnostico -Headers @{Authorization="Bearer <TOKEN>"}
npx wrangler secret delete DIAGNOSTICO_TOKEN                               # al terminar, desactívala
```

Esperado: `{"ok":true,"pasos":[{"paso":"salida_publica",…"ok"},{"paso":"oauth",…"ok"},{"paso":"firestore_autenticado","resultado":"ok","http":404}]}`
(`404` en un documento fijo inexistente, con la llamada autenticada autorizada, es correcto). Con un
token ausente o incorrecto responde 404; sin el secreto, la ruta se comporta como antes.

## 5. Si todavía fallara

Pega 2-3 líneas del `tail`. Cómo leerlas:

| Registro | Significado |
|---|---|
| `causa:"red"` + `errorCodigo:"invocacion_ilegal"` | Persistiría el problema de `this`: ¿se desplegó la versión nueva? |
| `causa:"red"` + `conexion_perdida` / `timeout` / `ECONNRESET` | Problema de red real hacia Google |
| `causa:"red"` + `limite_subpeticiones` | Se superó el límite de subpeticiones del plan |
| `causa:"red"` + `sin_clasificar` | Excepción no prevista: la clase (`errorNombre`) es la pista |
| `causa:"http"` + `http` + `googleStatus` | Google respondió: ahí sí aplican permisos/API/cuota |
