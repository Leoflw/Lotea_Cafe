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
  services/                    Arranque de Firebase, sincronización de fotos, navegación
cloudflare/imagekit-upload-auth/  Worker gratuito que autoriza las subidas a ImageKit
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
- Contraseñas: solo pasan a Firebase Authentication.

## Puesta en marcha

Sigue **[FIREBASE_SETUP.md](FIREBASE_SETUP.md)** paso a paso (incluye generar
`android/`, que no existía en el proyecto recibido).

```bash
flutter pub get && flutter analyze && flutter test
flutter run --dart-define-from-file=env.json   # ver IMAGEKIT_SETUP.md (copia env.example.json)
```

Sin los valores de ImageKit la app funciona, pero subir fotos muestra «La
subida de fotos no está configurada todavía».

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
subida a ImageKit y fallos de red. El Worker tiene sus propias pruebas
(`cd cloudflare/imagekit-upload-auth && npm test`).

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
