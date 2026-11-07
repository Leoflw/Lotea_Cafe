# Notificaciones push de Lotea Café (v5)

Arquitectura real implementada: **Firebase Cloud Messaging (FCM HTTP v1)** + un
**Cloudflare Worker independiente** (`cloudflare/push-notifications/`). Sin Cloud
Functions y sin plan Blaze. El Worker de ImageKit **no se modificó** (comprobado con `diff -r`
contra la v4).

```
App (Flutter) ──(1) Firestore: guarda mensaje / evento de cotización ──► confirmado
      │
      └─(2) POST /notify {tipo, ids}  + ID token de Firebase ──► Worker push-notifications
                                                                   │ verifica token y evento real (Firestore)
                                                                   │ deduce destinatario, lee sus dispositivos
                                                                   │ deduplica en Firestore (pushDedupe)
                                                                   └─(3) FCM HTTP v1 ──► dispositivo del destinatario
```

## Qué quedó implementado y qué requiere tu acción

| Pieza | Estado |
|---|---|
| Worker `cloudflare/push-notifications` (código, `wrangler.toml`, pruebas, README) | Implementado. **88 pruebas `node:test` ejecutadas: 88 aprobadas.** |
| Aviso tras confirmar el chat y cada evento de cotización | Implementado (Flutter), **sin compilar ni ejecutar** |
| Registro de dispositivos `users/{uid}/deviceTokens/{tokenId}` | Implementado (Flutter), sin ejecutar |
| Reglas de Firestore (`deviceTokens`, `pushDedupe`) | Escritas; **sin probar en el emulador**; **debes publicarlas** |
| Permiso `POST_NOTIFICATIONS`, canal, icono, opción en «Mi cuenta» | Implementado, sin compilar |
| Aviso en primer plano y apertura de `ChatScreen` / `QuoteDetailScreen` | Implementado, sin ejecutar |
| Cuenta de servicio y secreto `FCM_SERVICE_ACCOUNT_JSON` | **Acción tuya** (no hay credenciales en el proyecto) |
| Desplegar el Worker, configurar su URL, publicar reglas | **Acción tuya** |
| Medir la CPU del Worker en Cloudflare | **Acción tuya** (ver sección CPU) |

## Eventos que notifican

Siempre **después** de que Firestore confirmó la operación; el aviso no se espera y su fallo
nunca deshace ni hace parecer fallida la operación.

- **Chat:** mensaje nuevo en conexión aceptada → al otro participante. Nunca al remitente.
- **Cotizaciones** (historial `quotes/{id}/events/{id}`): `solicitudCreada`, `revisionSolicitada`,
  `ofertaAceptada`, `ofertaRechazada`, `cancelada` → vendedor; `ofertaEnviada`,
  `solicitudRechazada` → comprador. No hay estados ni campos nuevos. `ofertaVencida` es un
  estado derivado de la vigencia (no genera evento) y por eso no notifica.

En `QuoteRepository` el id del evento se captura dentro de la transacción **reiniciándolo en
cada ejecución**; el aviso se lanza después de que `runTransaction` termina. Si la solicitud ya
existía (reintento), no hay evento nuevo y no se avisa. Si el envío al Worker falla por red o
5xx se reintenta una vez; el Worker deduplica, así que es seguro. Limitación: si la persona
cierra la app justo al enviar, el aviso puede no salir.

## Seguridad (resumen; detalle en `cloudflare/push-notifications/README.md`)

- La app envía solo `tipo` + ids. **Nunca** UID o token FCM del destinatario, texto o ruta
  (el Worker responde 400 si llegan).
- Token de Firebase verificado criptográficamente (firma, proyecto, emisor, caducidad, UID).
- El Worker comprueba autoría, participación, estado de la conexión, último mensaje y tipo de
  evento, y deduce el destinatario consultando Firestore.
- Deduplicación persistente en Firestore (`pushDedupe`), no en memoria. Comportamiento ante
  errores de FCM documentado en el README del Worker.
- Tokens inválidos: se borran solo si Google confirma que no existen; nunca por errores temporales.
- Textos genéricos; no hay contenido del chat en la pantalla de bloqueo.

## Configuración manual (pasos del propietario)

### 1. Instalar dependencias

```bash
flutter pub get                      # añade firebase_messaging y actualiza pubspec.lock
cd cloudflare/push-notifications && npm install && cd ../..
cd rules-tests && npm install && cd ..
```

`firebase_messaging: ^15.2.10` es la línea 15.x que acompaña a `firebase_core 3.15.2`,
`firebase_auth 5.7.0` y `cloud_firestore 5.6.12` (las versiones de `pubspec.lock`). **No pude
ejecutar `flutter pub get`** (sin Flutter ni red), así que no está confirmado contra pub.dev.
Si pub informa un conflicto, ejecuta `flutter pub add firebase_messaging` (elige la versión
compatible sin subir las demás) y **no** pases a la 16.x sin subir `firebase_core` a 4.x.
`pubspec.lock` conserva las versiones actuales: `pub get` solo añade las nuevas.

### 2. Cuenta de servicio y secreto

Sigue la sección «Cuenta de servicio» de `cloudflare/push-notifications/README.md` (cuenta
dedicada, rol con permisos mínimos) y guarda el JSON **solo** así:

```bash
cd cloudflare/push-notifications
npx wrangler secret put FCM_SERVICE_ACCOUNT_JSON
```

No lo pegues en el chat ni lo guardes en archivos del proyecto.

### 3. Publicar las reglas de Firestore (de forma controlada)

Cambios mínimos en `firestore.rules`: bloque `users/{uid}/deviceTokens/{tokenId}` (solo el
dueño; campos exactos `token`, `plataforma` = `android`, `updatedAt` = hora del servidor; token
de 20 a 4096 caracteres) y `pushDedupe` denegado a los clientes. Nada más cambia.

```bash
git diff firestore.rules                                        # revisa el cambio (si usas git; si no, compara con tu copia de la v4)
cd rules-tests && npm install && npm test && cd ..             # emulador (necesita Java y firebase-tools)
firebase deploy --only firestore:rules
```

Publica las reglas **antes** de probar el registro de dispositivos. Si algo falla, la consola
de Firebase (Firestore → Reglas) conserva el historial para volver a la versión anterior.
No hay índices nuevos.

### 4. Desplegar el Worker

```bash
cd cloudflare/push-notifications
npm test
npx wrangler login
npx wrangler deploy
```

### 5. Configurar la URL en la app

Con el mecanismo que ya usa el proyecto (`--dart-define-from-file`), en tu `env.json` local
(copiado de `env.example.json`, **no** se versiona):

```json
{ "PUSH_NOTIFICATIONS_ENDPOINT": "https://push-notifications.<tu-subdominio>.workers.dev" }
```

```bash
flutter run --dart-define-from-file=env.json
```

Sin esa URL la app funciona; simplemente no avisa a nadie.

### 6. Medir la CPU en Cloudflare

Ver «Límite de CPU» en el README del Worker. Mi medición **local** (Node, con Google simulado):
arranque en frío ≈ 4,1 ms (máx. 6,9 ms), caliente ≈ 1,6 ms frente al límite de 10 ms. **No
equivale a una medición en Cloudflare.** Si el p99 supera 10 ms, hay alternativas gratuitas
(KV + tarea programada, dominio propio con Cache API) antes de considerar el plan de pago.

### 7. Probar en el Samsung Galaxy A32 (Android 13)

1. Instala la app, inicia sesión, abre «Mi cuenta» y pulsa **Activar notificaciones** (aparece el
   diálogo del sistema).
2. Con dos cuentas en dos dispositivos, envía un mensaje y una cotización; prueba con la app
   en primer plano (aviso dentro de la app), en segundo plano y cerrada; toca la notificación.
3. Cierra sesión y comprueba en Firestore que desapareció el documento de `deviceTokens`.

## Experiencia en la app

- **Permiso:** el diálogo del sistema (Android 13+) **solo** aparece al pulsar «Activar
  notificaciones» en «Mi cuenta», nunca al abrir la app. Si lo rechazas, la app sigue
  igual y la tarjeta explica cómo activarlas desde Ajustes.
- En Android 12 o anterior el permiso ya está concedido por el sistema, así que el dispositivo
  se registra solo al iniciar sesión (el usuario puede desactivarlas en Ajustes del teléfono).
- **Primer plano:** `onMessage` muestra un aviso dentro de la app con texto propio y genérico
  y un botón «Ver». No se muestra si ya estás en ese chat.
- **Apertura:** `getInitialMessage` y `onMessageOpenedApp` abren `ChatScreen` o
  `QuoteDetailScreen` con el `navigatorKey` existente. Si la sesión aún se resuelve, el destino
  se conserva y se abre cuando el perfil y el onboarding están listos; sin sesión se descarta.
  Antes de abrir se comprueba que el recurso existe y que la persona participa; si no,
  se avisa «Este contenido ya no está disponible».
- **Texto:** «Tienes un nuevo mensaje en Lotea Café» / «Tienes novedades en una cotización».

## Tokens de dispositivo

`users/{uid}/deviceTokens/{tokenId}` con **solo** `token`, `plataforma`, `updatedAt`. El
`tokenId` es un UUID v5 derivado del token (estable, único, sin revelarlo). Varios dispositivos
por usuario; `onTokenRefresh` guarda el nuevo y borra el anterior.

Al **cerrar sesión**, `SessionProvider` ejecuta antes (máx. 5 s, sin bloquear el cierre) el
borrado del registro de esa cuenta y `deleteToken()` de FCM. Si la sesión cambia sin pasar por
«Cerrar sesión» (p. ej. sesión revocada), ya no se puede borrar el registro de la cuenta
anterior (las reglas no lo permiten): se invalida el token y el Worker limpia ese registro la
primera vez que FCM lo marque `UNREGISTERED`.

## Pruebas

| Suite | Comando | Estado |
|---|---|---|
| Worker de notificaciones (88) | `cd cloudflare/push-notifications && npm test` | **Ejecutada: 88/88** |
| Worker de ImageKit (26) | `cd cloudflare/imagekit-upload-auth && npm test` | **Ejecutada: 26/26** (código idéntico a v4) |
| Flutter (185 de la v4 + nuevas) | `flutter pub get && flutter test` | **No ejecutada** (sin Flutter en el entorno) |
| `flutter analyze` | `flutter analyze` | **No ejecutado** |
| Reglas de Firestore | `cd rules-tests && npm install && npm test` | **No ejecutada** (sin Java/emulador/red) |

Pruebas Flutter nuevas: `push_notification_client_test`, `device_token_service_test`,
`push_navigation_test`, `push_repositories_test`, `session_logout_hook_test`,
`push_activation_card_test`. Reglas nuevas: `rules-tests/device_tokens.rules.test.js`.

**Reglas de Firestore:** en la v4 las 13 pruebas de `rules-tests` no arrancaron porque faltaba
`@firebase/rules-unit-testing`. Primero instala las dependencias **dentro de `rules-tests`**
(`npm install`) y luego repite la suite. Esta entrega no afirma que pasen.

`flutter analyze` mostraba 35 avisos informativos en la v4. Revisé el de `BuildContext` en
`quote_detail_screen.dart`: tras `await Navigator…push`, el código comprobaba el `mounted` del
`State` pero usaba el `context` de `build()`; ahora comprueba `context.mounted`. No pude volver
a ejecutar el analizador para confirmarlo.

## Limitaciones conocidas

- Mi entorno no tenía Flutter, Dart ni red: **el código Dart/Kotlin/XML no se compiló** y puede
  necesitar ajustes menores al primer `flutter analyze`.
- Si alguien envía dos mensajes seguidos muy rápido, el aviso del primero se descarta (409)
  porque ya no es el último de la conexión; llega el del segundo.
- Los avisos solo se aceptan hasta 15 minutos después del hecho.
- El limitador de 60 avisos/10 min es por instancia del Worker (mejor esfuerzo); la protección
  real es la deduplicación persistente.
- Se notifica a un máximo de 10 dispositivos por destinatario.
- Canal de Android único («Mensajes y cotizaciones»); no hay preferencias por tipo de aviso ni
  contador de no leídos en el icono.
- iOS no está configurado (el proyecto solo tiene Android).
