# Lotea Café

**Descubre. Compara. Conecta.** — marketplace móvil de café colombiano
(Flutter + Dart) que conecta productores/vendedores con compradores
(cafeterías, tostadores, restaurantes, distribuidores).

Antes se llamaba CaféMatch. Esta es la **cuarta ronda de mejoras**: migración
de datos locales a Firebase, nueva identidad y flujo completo de cotizaciones.

> **Estado honesto de esta entrega:** el código se escribió sin acceso a
> Flutter, Dart, Firebase ni red, así que **no se ha compilado, analizado ni
> ejecutado**. Ver «Qué falta verificar» antes de confiar en él.

## Qué hace la app

- **Comprador:** descubre cafés (tarjetas o lista), filtra y busca, guarda
  cafés/vendedores, envía solicitudes de interés, chatea con vendedores que
  aceptan, solicita cotizaciones y acepta/rechaza/pide ajustes a las ofertas.
- **Vendedor:** crea el perfil de su marca, publica cafés (borrador o
  publicado) con fotos, responde solicitudes de interés y cotizaciones.
- **No incluye** pagos, pedidos, logística ni notificaciones push. Aceptar una
  oferta solo registra el acuerdo.

## Arquitectura

```
lib/
  main.dart                    Arranque: Firebase → providers → AuthGate
  models/                      Datos puros (fromMap/toMap), sin Firebase salvo data/codec.dart
  repositories/                ÚNICA capa que habla con servicios externos (Firebase Auth, Firestore, ImageKit)
  state/                       SessionProvider (sesión+rol), ActivityProvider (datos propios en vivo)
  config/imagekit_config.dart  URL del Worker + public key de ImageKit (públicas, vía --dart-define)
  config/push_config.dart      URL del Worker de notificaciones (pública, vía --dart-define)
  services/                    Arranque de Firebase, fotos, navegación, notificaciones push (push_*, device_token_service)
cloudflare/imagekit-upload-auth/  Worker gratuito que autoriza las subidas a ImageKit
cloudflare/push-notifications/    Worker gratuito, independiente, que envía las notificaciones por FCM
  utils/catalog_logic.dart     Filtros, búsqueda, orden y relevancia (lógica pura, probada)
  screens/ widgets/ theme/     Interfaz
```

- Las pantallas **no conocen Firestore**: usan repositorios y providers.
- **Sin datos demo, sin `MockStore`, sin acceso rápido.** Si Firebase no está
  configurado, la app muestra «Falta conectar Firebase» con los pasos.
- `ActivityProvider` escucha solo los datos *propios* del usuario (solicitudes,
  cotizaciones, favoritos; o perfil y lotes si es vendedor) y se vacía al
  cerrar sesión. El catálogo público se consulta por páginas de 20.
- Los errores son tipados (`RepoException`): sin conexión, sin permisos,
  configuración pendiente (índice/ImageKit/Auth), etc. **Un error nunca se
  muestra como lista vacía.**

## Modelo de datos (Firestore)

| Colección | Id | Notas |
|---|---|---|
| `users/{uid}` | UID | Rol (`comprador`/`vendedor`) inmutable; sin contraseñas. |
| `users/{uid}/favorites/{tipo}_{refId}` | determinista | Sin duplicados. |
| `sellerProfiles/{uid}` | UID | `verificado`, `calificacionPromedio`, `numOperaciones` no escribibles desde la app. |
| `coffeeLots/{id}` | auto | Copia `sellerNombreMarca/departamento/…` para listar sin leer el perfil. |
| `interestRequests/{compradorId}_{loteId}` | determinista | Evita solicitudes duplicadas; rechazada → se puede reabrir. |
| `chats/{conexión}/messages/{id}` | uuid del cliente | Solo con conexión aceptada; reintento idempotente. |
| `quotes/{id}` + `events/{id}` | uuid del cliente | Cotización + historial inmutable. |

Las copias de visualización (`loteNombre`, `compradorNombre`, …) en solicitudes
y cotizaciones **no son fuente de verdad**: evitan una lectura por tarjeta.

## Cotizaciones

Estados: `solicitudPendiente → ofertaEnviada → ofertaAceptada | ofertaRechazada |
revisionSolicitada → (nueva oferta) …`, más `solicitudRechazada`, `cancelada` y
`ofertaVencida` (derivado de la vigencia; no se escribe).

- La tabla de transiciones vive en `QuoteStateMachine` y se **repite** en
  `firestore.rules`; los repositorios la validan dentro de una transacción
  que también escribe el evento de historial.
- Importes en pesos enteros: `subtotal = cantidad × precio`, `total = subtotal
  + envío` (`QuoteCalculator`; las reglas lo verifican).
- La unidad del precio es la de la solicitud (sin conversiones).
- Solo se cotiza dentro de una conexión **aceptada**.

## Seguridad

- `firestore.rules`: todo exige sesión; cada usuario ve solo lo suyo; el
  catálogo publicado es legible por autenticados; validación de campos,
  longitudes, propiedad y transiciones.
- Fotos: se alojan en **ImageKit** (plan gratuito). La app sube con una
  autorización temporal que entrega un **Cloudflare Worker** tras validar el
  token de Firebase y el rol `vendedor`. La clave privada de ImageKit solo
  existe como secreto del Worker. Detalle y límites en
  **[IMAGEKIT_SETUP.md](IMAGEKIT_SETUP.md)**. `storage.rules` ya no se usa.
- Notificaciones push: FCM HTTP v1 desde un **Worker independiente** que verifica el token de
  Firebase y el evento real en Firestore y deduce el destinatario; la app nunca indica a quién
  avisar. La cuenta de servicio vive solo como secreto del Worker. Ver
  **[PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md)**.
- Contraseñas: solo pasan a Firebase Authentication.

## Puesta en marcha

Sigue **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** paso a paso (incluye generar
`android/`, que no existía en el proyecto recibido).

```bash
flutter pub get && flutter analyze && flutter test
flutter run --dart-define-from-file=env.json   # ver IMAGEKIT_SETUP.md (copia env.example.json)
```

Sin los valores de ImageKit la app funciona, pero subir fotos muestra «La
subida de fotos no está configurada todavía». Sin `PUSH_NOTIFICATIONS_ENDPOINT` la app
funciona y simplemente no envía avisos.

## Identidad visual (`assets/branding/`)

| Archivo | Uso |
|---|---|
| `lotea_cafe_symbol.png` | Símbolo (grano + hoja), PNG transparente y sin texto. Es el único recurso de marca que se empaqueta en la app. |
| `lotea_cafe_icon_foreground.png` | Primer plano transparente (1024 px) del icono adaptativo de Android. |
| `lotea_cafe_icon.png` | Símbolo sobre crema `#FBF3E7` (1024 px, opaco): fuente del icono clásico. |
| `lotea_cafe_logo.png` | Logotipo horizontal original. Tiene el fondo crema incrustado, por eso **ya no se usa en la app** (se conserva solo como referencia de marca). |

- **Encabezado de marca:** `LoteaBrandHeader` (`lib/widgets/brand_header.dart`)
  compone símbolo + «Lotea Café» + eslogan con widgets. Lo usan inicio de
  sesión, onboarding, completar perfil, pantalla de espera y pantalla de
  configuración pendiente. Admite variante clara/oscura, eslogan opcional,
  tamaños y alineación.
- **Nombre visible:** `res/values/strings.xml` (`app_name` = «Lotea Café»).
  El `applicationId` sigue siendo `com.loteacafe.lotea_cafe`.
- **Icono nativo:** `flutter_launcher_icons` (configurado en `pubspec.yaml`)
  genera `mipmap-*`, `drawable-*/ic_launcher_foreground.png`,
  `mipmap-anydpi-v26/ic_launcher.xml` y `values/colors.xml` (fondo `#FBF3E7`).
  Los recursos incluidos se generaron con un script equivalente porque en el
  entorno de esta fase no había Flutter; al ejecutar el comando se
  sobrescriben con los de la herramienta:

  ```bash
  flutter pub get
  dart run flutter_launcher_icons
  ```

## Pruebas incluidas (`test/`)

`test/brand_ui_test.dart`: encabezado de marca, tarjetas de rol del registro
(mismo tamaño con cualquier selección), etiqueta del nombre según rol y
ausencia de desbordamientos en login (pantalla pequeña y teclado abierto).

Lógica pura, sin Firebase: máquina de estados y cálculo de cotizaciones,
validaciones, filtros/búsqueda/orden/relevancia, serialización de lotes,
traducción de errores de Firebase, validación de imágenes (tipo/tamaño), reglas
de borrador/publicación y URLs de ImageKit. Con `fake_cloud_firestore`:
persistencia de URLs en Firestore y catálogo. Con `MockClient`: autorización,
subida a ImageKit y fallos de red. Los Workers tienen sus propias pruebas
(`cd cloudflare/imagekit-upload-auth && npm test` y
`cd cloudflare/push-notifications && npm test`).

Notificaciones push (v5): `push_notification_client_test`, `device_token_service_test`,
`push_navigation_test`, `push_repositories_test`, `session_logout_hook_test`,
`push_activation_card_test` (Flutter, **sin ejecutar**) y `rules-tests/device_tokens.rules.test.js`
(**sin ejecutar**). El Worker nuevo tiene 88 pruebas, ejecutadas y aprobadas.

## Quinta ronda: pulido de fotos, cuenta y mensajes

### Límites de fotografías

| Dónde | Máximo | Se aplica en |
|---|---|---|
| Cada café | **5 fotos** en total (la primera es la principal; «Hacer principal» la cambia) | `PhotoLimits` · `CoffeeLotEditScreen` (contador «3 de 5 fotos») · `CoffeeLotRepository.guardarLote` · `firestore.rules` (`coffeeLots`) |
| Galería de marca | **6 fotos adicionales** (la foto principal de la marca es aparte y no cuenta) | `PhotoLimits` · `SellerProfileEditScreen` (contador «2 de 6 fotos de galería») · `SellerRepository.guardarPerfil` · `firestore.rules` (`sellerProfiles`) |

Los números viven en `lib/utils/photo_limits.dart`; `test/photo_limits_test.dart`
lee `firestore.rules` y falla si dejan de coincidir.

**Datos antiguos (límites anteriores de 10 y 12).** No se recortan ni se migran.
Un documento con más fotos que el máximo se puede seguir editando (nombre,
precio…) y guardar con la misma cantidad o con menos, de modo que su dueño las
reduzca cuando quiera; lo que nunca puede es **aumentar** su cantidad por encima
del máximo. Es la función `photoCountOk` de las reglas y `PhotoLimits.validarCantidad`
en la app. Quitar una foto no la borra de ImageKit (ver limitaciones).

Un borrador se guarda sin fotos; publicar exige al menos una foto subida
correctamente y ninguna pendiente o fallida (`LotPublishPolicy`).

### Foto de la marca en «Mi cuenta» y «Mi catálogo»

El círculo de la cabecera usa `AvatarCircular` con la `fotoPrincipal` del
`sellerProfiles/{uid}` del vendedor con sesión (`AvatarLogic.fotoDeCuenta`). Si
no hay foto, mientras carga o si la imagen falla, muestra la inicial. Un
comprador siempre ve su inicial (no tiene foto personal) y nunca la foto de un
vendedor. El perfil se escucha en tiempo real, así que al guardar otra foto de
marca la cabecera cambia sin cerrar sesión. La foto de las tarjetas de café es
otra cosa (`CoffeeLot.fotoPrincipal`, la primera URL remota de ese café).

### Mensajes no leídos

Estado en la conexión (`interestRequests/{id}`), sin colecciones nuevas:

- `ultimoMensajeAt` y `ultimoMensajeDe`: los escribe quien envía, en el **mismo
  lote atómico** que el mensaje (`ChatRepository.enviar`).
- `leidoComprador` y `leidoVendedor`: cada participante escribe **solo el suyo**
  al abrir el chat con la app en primer plano (`marcarChatLeido`).
- Hay mensajes sin leer para una persona si el último mensaje **no** es suyo y es
  posterior a su marca de lectura (`InterestRequest.tieneMensajesNoLeidos`).

Se muestra un punto en el icono de chat de la conexión (vendedor) o en el botón
«Chat» (comprador), en la pestaña «Conexiones» y en la insignia de «Solicitudes».
La insignia suma, cada una una sola vez: solicitudes por responder, cotizaciones
que esperan acción y **conversaciones** con mensajes sin leer.
Es un punto, no un número de mensajes: contar mensajes exigiría una consulta por
conversación o que el remitente escribiera en el estado del destinatario, lo que
las reglas no permiten. Las conversaciones anteriores a esta versión empiezan sin
indicador hasta su siguiente mensaje.

### Reglas de Firestore: revisar y publicar

Cambios en `firestore.rules`: función `photoCountOk` y límites 5/6; en
`interestRequests`, la función `chatStateUpdate` (solo conexiones aceptadas; cada
participante solo su `leido…`; `ultimoMensajeDe` debe ser el uid de quien escribe;
no toca `updatedAt`). Todo lo demás queda igual.

1. Lee el bloque `interestRequests` y las dos llamadas a `photoCountOk`.
2. (Opcional) Pruébalas: `firebase emulators:start --only firestore` o el
   «Simulador de reglas» de la consola de Firebase.
3. Publica con `firebase deploy --only firestore:rules` (o pega el archivo en
   Firestore → Reglas → Publicar).
4. **Publica las reglas ANTES de probar el chat con la app nueva**: enviar un
   mensaje ahora actualiza también la conexión, y con las reglas anteriores
   Firestore rechazaría el envío.

**Seguridad del «último mensaje».** Escribir `ultimoMensajeAt/De/Id` solo se
acepta si en la misma operación atómica se crea el mensaje `ultimoMensajeId`
(`exists`/`getAfter` en las reglas: no existía antes, existe después, su remitente
es quien escribe y su `createdAt` es la hora del servidor). Pruebas reales de
reglas contra el emulador en `rules-tests/` (`npm install && npm test`; necesita
Java y firebase-tools). `test/chat_rules_text_test.dart` solo vigila el texto de
las reglas y **no** las prueba.

No hay índices nuevos.

## Sexta ronda: notificaciones push

Implementadas con FCM + Worker independiente (`cloudflare/push-notifications/`): mensajes de
chat y los 7 eventos de cotización, registro de dispositivos en `users/{uid}/deviceTokens`, opción
«Activar notificaciones» en «Mi cuenta», aviso en primer plano y apertura de `ChatScreen` /
`QuoteDetailScreen`. Reglas nuevas: `deviceTokens` (solo el dueño) y `pushDedupe` (solo el
Worker). **Guía completa, comandos, secretos y estado de las pruebas: [PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md).**
Requiere acciones manuales: cuenta de servicio y secreto, desplegar el Worker, configurar su URL
y publicar las reglas.

## Limitaciones conocidas

1. **Filtros del catálogo:** Firestore solo filtra por `estado` y ordena por
   fecha o precio; variedad, proceso, departamento, precio, altitud,
   puntaje, certificaciones y texto se aplican **en el cliente sobre las
   páginas ya descargadas** (hasta 5 páginas por pulsación; botón «Buscar más
   cafés»). Con catálogos grandes conviene añadir filtros/índices en el
   servidor o un buscador dedicado.
2. «Mayor puntaje» y «mayor disponibilidad» ordenan solo lo descargado (los
   lotes sin ese dato desaparecerían de un `orderBy` de Firestore).
3. Los descartes de Descubrir duran solo la sesión.
4. Fotos huérfanas: al quitar o reemplazar una foto, el archivo **queda en
   ImageKit** (borrar exige la clave privada y esta entrega no añade un endpoint
   de borrado al Worker). El `fileId` queda guardado en Firestore para poder
   limpiarlas luego desde el panel de ImageKit o con un endpoint futuro.
5. Un vendedor que cambie el nombre de su marca no actualiza las copias en
   lotes ya publicados hasta que guarde cada lote.
6. Verificación de vendedores y calificaciones: campos preparados, sin proceso.
7. Solo Android generado; iOS pendiente.
8. El símbolo e iconos se recortaron de una imagen raster; sustituir por el vectorial.
9. Las tarjetas de solicitudes, conexiones y cotizaciones muestran una **copia** de
   la foto del café tomada al crearlas (`loteFoto`): si el vendedor cambia después
   la foto principal del café, esas copias no se actualizan.
10. El indicador de mensajes es un punto, no un contador por mensajes.
11. La otra persona puede ver la hora de tu última lectura (`leido…` está en el
    mismo documento que ambos pueden leer).

## Qué falta verificar (no se pudo ejecutar)

- `flutter pub get` — las versiones de Firebase en `pubspec.yaml` son de
  referencia y no se resolvieron.
- `flutter analyze` y compilación: cero ejecuciones. Solo se comprobó
  estáticamente que no haya imports inexistentes ni llaves desbalanceadas.
- Pruebas unitarias escritas, **no ejecutadas**.
- Reglas de Firestore: **no probadas en el emulador**. Revisarlas
  con `firebase emulators:start` y pruebas de reglas antes de producción.
- Recorrido manual comprador ↔ vendedor en dispositivo.
- Fase visual: icono en el menú de apps, nombre «Lotea Café», login,
  registro y onboarding **no se vieron en un dispositivo ni emulador**;
  `test/brand_ui_test.dart` está escrito pero **no se ejecutó**.
- Quinta ronda: **nada se ha ejecutado** (no hubo Flutter, Dart ni red en el
  entorno de desarrollo). Las pruebas nuevas — `photo_limits_test`,
  `account_avatar_test`, `unread_messages_test`, `lot_cover_photo_test`,
  `plural_labels_test` — están escritas pero **sin ejecutar**; tampoco las
  reglas nuevas en el emulador ni el comportamiento en el Samsung Galaxy A32.
- Sexta ronda (push): el Worker nuevo se probó con 88 pruebas `node:test` (aprobadas) y el de
  ImageKit con sus 26 (aprobadas, código sin cambios). **No se ejecutó** `flutter pub get`,
  `flutter analyze`, `flutter test`, la compilación Android ni las reglas en el emulador
  (el entorno no tenía Flutter, Dart, Java ni red). La CPU del Worker solo se midió en local,
  no en Cloudflare.
