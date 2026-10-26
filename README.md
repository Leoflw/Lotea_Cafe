# CaféMatch → Marketplace de café (evolución del MVP)

Evolución del MVP "Tinder del café" hacia una plataforma de marketplace:
el swipe se conserva como mecanismo *opcional* de descubrimiento, pero el
centro de la app pasa a ser DESCUBRIR → VER PERFIL COMPLETO → MOSTRAR
INTERÉS → SOLICITUD → CONEXIÓN COMERCIAL → CHAT → COTIZACIÓN.

Sigue sin backend real (todo vive en memoria, como en la build de pruebas
anterior) porque así se decidió explícitamente para esta iteración. La
arquitectura de datos está organizada en colecciones equivalentes a las
que tendría Firestore, para que migrar sea un cambio de capa de datos, no
de arquitectura — ver la sección "Camino a Firestore" más abajo.

## Cómo correrla

```bash
cd cafe_match_marketplace
flutter pub get
flutter run                      # con el teléfono conectado
# o
flutter build apk --release      # genera build/app/outputs/flutter-apk/app-release.apk
```

Al abrir, usa "Entrar como comprador demo" para saltarte el registro, o
crea una cuenta eligiendo "Vender café" / "Comprar café". Hay 5 fincas
colombianas de ejemplo (Huila, Antioquia, Nariño, Quindío, Tolima) con
varios lotes cada una, ya publicadas.

---

## Resumen de la evolución (punto 32 del plan)

### Archivos modificados (reutilizados, no reescritos desde cero)
- `lib/services/session_provider.dart` — se agregó `actualizarUsuario()`
- `lib/screens/auth/login_screen.dart` — lenguaje de marketplace
- `lib/screens/auth/register_screen.dart` — selección "Vender/Comprar café", ciudad y tipo de comprador
- `lib/screens/home/home_shell.dart` — navegación reestructurada
- `lib/screens/profile/my_profile_screen.dart` — preferencias (comprador) / resumen de marca (vendedor)
- `lib/widgets/swipe_card.dart` — rediseñada con toda la info + botón "Ver perfil"
- `lib/theme/app_theme.dart` — sin cambios de fondo, reutilizado tal cual
- `pubspec.yaml` — descripción actualizada (mismas dependencias)

### Archivos nuevos
**Modelos**: `seller_profile.dart`, `coffee_lot.dart`, `interest_request.dart`, `favorite.dart`, `quote_request.dart`
**Utilidades**: `utils/format_utils.dart` (formato COP)
**Widgets**: `empty_state.dart`, `badges.dart`, `coffee_lot_card.dart`, `interest_dialog.dart`
**Pantallas**: `discover/discover_screen.dart`, `discover/swipe_mode_view.dart`, `discover/list_mode_view.dart`, `discover/filters_sheet.dart`, `seller/seller_detail_screen.dart`, `seller/seller_profile_edit_screen.dart`, `seller/my_coffee_lots_screen.dart`, `seller/coffee_lot_edit_screen.dart`, `coffee/coffee_lot_detail_screen.dart`, `requests/my_requests_screen.dart`, `requests/received_requests_screen.dart`, `saved/saved_screen.dart`, `chat/quote_request_screen.dart`, `onboarding/onboarding_screen.dart`

### Archivos eliminados (reemplazados conceptualmente)
- `models/coffee_profile.dart` → dividido en `SellerProfile` + `CoffeeLot`
- `models/match_model.dart` → reemplazado por `InterestRequest`
- `screens/swipe/swipe_screen.dart` → reemplazado por `discover/discover_screen.dart` + `swipe_mode_view.dart`
- `screens/matches/matches_screen.dart` → reemplazado por `requests/my_requests_screen.dart` y `requests/received_requests_screen.dart`
- `screens/profile/seller_profile_edit_screen.dart` (antiguo, mezclaba vendedor+café) → dividido en `seller/seller_profile_edit_screen.dart` + `seller/coffee_lot_edit_screen.dart`

### Modelos: creados/modificados
| Modelo | Cambio |
|---|---|
| `AppUser` | + ciudad, tipoComprador, preferencias (variedades/regiones/procesos/precioMax) |
| `SellerProfile` (nuevo) | Reemplaza la mitad "vendedor" de `CoffeeProfile`: marca, finca, galería, historia, verificación, reputación |
| `CoffeeLot` (nuevo) | Reemplaza la mitad "café" de `CoffeeProfile`: un vendedor puede tener N lotes, con perfil sensorial, certificaciones, precio COP |
| `InterestRequest` (nuevo) | Reemplaza `MatchModel`: pendiente → aceptada/rechazada, sin "like" automático |
| `Favorite` (nuevo) | Guardados de café/vendedor, separado de las solicitudes |
| `QuoteRequest` (nuevo) | Arquitectura preparada para cotización → pedido → pago |

### "Colecciones" de datos (equivalente a Firestore, hoy en `MockStore`)
Antes: `usuarios · perfiles_cafe · likes · matches · chats`
Ahora: `usuarios · vendedores · lotes · solicitudes · favoritos · cotizaciones · mensajes`

Sin duplicación: `SellerProfile` no repite nombre/email del usuario (usa
`usuarioId` como referencia); `CoffeeLot` no repite datos del vendedor
(usa `sellerId`); el chat no repite datos de la solicitud (usa el id de
la `InterestRequest` como `chatId`).

### Camino a Firestore (si se retoma la versión con backend)
- `usuarios/{uid}` — igual que antes
- `vendedores/{sellerId}` — antes `perfiles_cafe`, ahora solo datos de marca
- `vendedores/{sellerId}/lotes/{loteId}` — subcolección, así "lotes de un vendedor" es una query directa sin filtrar del lado del cliente
- `solicitudes/{id}` — con índice compuesto `(compradorId, fecha desc)` y `(sellerId, estado, fecha desc)` para las dos pantallas de solicitudes sin descargar todo
- `favoritos/{id}` — índice `(compradorId, tipo)`
- `cotizaciones/{id}` — índice `(interestRequestId, fecha desc)`
- `chats/{interestRequestId}/mensajes/{id}` — el chat solo existe si la solicitud está aceptada (regla de seguridad lo valida)

Reglas conceptuales a portar: comprador solo crea sus propias solicitudes;
vendedor solo acepta/rechaza las dirigidas a él; chat legible solo por
`compradorId`/`sellerId` de la solicitud asociada; favoritos son privados
del comprador dueño; lotes con `estado == publicado` son de lectura
pública, el resto solo por su dueño.

### Nuevas pantallas
`SellerDetailScreen`, `CoffeeLotDetailScreen`, `DiscoverScreen` (+ modo tarjetas/lista), `MyRequestsScreen`, `ReceivedRequestsScreen`, `SavedScreen`, `MyCoffeeLotsScreen`, `SellerProfileEditScreen`, `CoffeeLotEditScreen`, `QuoteRequestScreen`, `OnboardingScreen`

### Nuevas funcionalidades
- Perfil de vendedor completamente explorable (galería, historia, cafés)
- Un vendedor puede publicar varios lotes de café
- Sistema de solicitudes comerciales con estados pendiente/aceptada/rechazada (sin "match" automático)
- Chat habilitado solo tras conexión comercial, con contexto (café + precio) y botón "Ver café"
- Solicitud de cotización (cantidad, unidad, lugar de entrega) — arquitectura lista para pedido/pago futuro
- Filtros ampliados: departamento, variedad, proceso, precio, altitud, puntaje, certificaciones, disponibilidad, tipo de café, vendedor verificado
- Modo lista además del modo swipe
- Favoritos separados en cafés/vendedores guardados
- Preferencias de compra del comprador (variedades, regiones, procesos)
- Precios en formato COP colombiano (`$32.000 / kg`)
- Insignia de verificado (solo cuando el dato existe), certificaciones, disponibilidad, calificación
- Onboarding con mensaje distinto para comprador/vendedor tras registrarse

### Terminología (sección 1) — aplicada en toda la app
Se eliminó "match/like/¿te gusta?" y se reemplazó por: Me interesa · Descartar · Ver perfil · Solicitar contacto · Mis solicitudes · Conexión comercial · Solicitudes recibidas · Aceptar/Rechazar solicitud · Compradores interesados.

### Mejoras dejadas preparadas pero NO implementadas (a propósito, sección 30)
- Persistencia real (Firestore) — estructura ya compatible, ver arriba
- Pagos, pedidos, envíos, facturación — `QuoteRequest` es el punto de partida
- Notificaciones push (nuevo mensaje, solicitud aceptada)
- Verificación real de vendedores (hoy es un campo booleano de demo)
- Calificaciones post-transacción
- Recomendación personalizada basada en `BuyerPreferences`
- Panel administrativo / analítica

### Calidad de código (sección 31)
No pude ejecutar `flutter analyze` ni pruebas automatizadas en este
entorno (no tiene el SDK de Flutter instalado). Sí hice verificación
estática manual: balance de llaves/paréntesis en los 36 archivos,
cruce de cada import relativo contra el árbol de archivos, y revisión
de que ninguna pantalla quedó referenciando clases eliminadas
(`CoffeeProfile`, `MatchModel`). Antes de tu primera prueba real,
corre `flutter analyze` en tu máquina — con este volumen de código es
razonable que aparezca algún ajuste menor de tipos u imports.

---

## Segunda ronda de mejoras (pulido hacia "producto")

Objetivo: pasar de "MVP funcional" a "prototipo pulido presentable". Sigue
sin Firebase/pagos reales — todo en `MockStore`, diseñado para migrar a
Firestore sin rehacer la UI (los widgets no saben de dónde vienen los datos).

### Funcionalidades nuevas
- **Visor de imágenes a pantalla completa** (`FullscreenImageViewer`): zoom con pellizco, swipe entre fotos, contador "2/5", cierre con X o deslizando hacia abajo. Reutilizado en perfil de vendedor, galería del café, formularios de fotos y tarjetas.
- **`AppImage`**: componente único que reemplazó los ~10 usos sueltos de `Image.file`/`FileImage` en toda la app — centraliza placeholder, error y apertura del visor.
- **Búsqueda + orden + filtros** en Descubrir: barra de búsqueda (café, variedad, finca, región, proceso), 6 criterios de orden, contador "X cafés encontrados" y "Limpiar filtros".
- **Prevención de solicitudes duplicadas**: `MockStore.crearSolicitud` ahora valida y lanza `DuplicateRequestException` con el mensaje correcto según el estado existente (pendiente/aceptada).
- **Descartes con "Deshacer"**: al descartar un café aparece un snackbar con acción "Deshacer" (solo el último descarte, como pide el PDF).
- **Recomendaciones simples** (`MockStore.puntuarLote` / `coincideConPreferencias`): puntuación por coincidencia de variedad/proceso/región/precio/disponibilidad contra las preferencias del comprador; se usa para el orden "Más relevantes" y la etiqueta "Coincide con tus preferencias" en las tarjetas.
- **Galería del café** con imagen grande, indicador de posición y miniaturas — funciona igual con 1 o con 10 fotos.
- **Perfil sensorial visual**: barras de progreso para Acidez/Cuerpo/Dulzor en vez de solo texto.
- **Sección "Origen"** con ícono por dato (finca, municipio, departamento, país, altitud).
- **Sección de confianza** en el perfil del vendedor: checklist ✓ que solo muestra indicadores respaldados por datos reales (nunca inventados).
- **"Mi catálogo"** del vendedor con estadísticas (cafés publicados, solicitudes pendientes, conexiones).
- **Gestión de fotos mejorada**: eliminar, ver en grande y elegir foto principal, tanto en el perfil de vendedor como en cada lote.
- **Chat con encabezado comercial**: foto+nombre+precio del café, botones explícitos [Ver café] / [Cotizar].
- **Cotización con resumen dinámico** antes de enviar ("Estás solicitando cotización de X kg de...").
- **Validaciones**: precio > 0, cantidad > 0, altitud ≥ 0, puntaje entre 50-100, variedad/proceso obligatorios.
- **Formulario de café dividido visualmente** en secciones (Fotografías, Identidad, Proceso y calidad, Venta, Certificaciones y envío) sin convertirlo en wizard.
- **Accesibilidad**: botones del swipe con etiqueta de texto + `Tooltip` + `Semantics`, no solo íconos.
- Sexto vendedor de demo (Cauca) para mayor diversidad regional.

### Archivos nuevos
`widgets/app_image.dart`, `widgets/fullscreen_image_viewer.dart`

### Archivos modificados (más relevantes)
`data/mock_store.dart` (búsqueda/orden/duplicados/recomendación/deshacer), `screens/discover/discover_screen.dart`, `screens/discover/swipe_mode_view.dart`, `screens/coffee/coffee_lot_detail_screen.dart`, `screens/seller/seller_detail_screen.dart`, `screens/seller/seller_profile_edit_screen.dart`, `screens/seller/coffee_lot_edit_screen.dart`, `screens/seller/my_coffee_lots_screen.dart`, `screens/chat/chat_screen.dart`, `screens/chat/quote_request_screen.dart`, `screens/requests/my_requests_screen.dart`, `screens/requests/received_requests_screen.dart`, `screens/saved/saved_screen.dart`, `screens/onboarding/onboarding_screen.dart`, `screens/profile/my_profile_screen.dart`, `screens/home/home_shell.dart`, `widgets/swipe_card.dart`, `widgets/coffee_lot_card.dart`

### Cambios en modelos
Ningún modelo de datos cambió de forma incompatible; `DiscoverFilters` ganó `busqueda` y `orden` (con defaults, no rompe nada existente).

### Cambios en MockStore
`DuplicateRequestException`, `DiscoverSort` (enum + comparador), `puntuarLote`/`coincideConPreferencias`, `deshacerUltimoDescarte`, `descubrirLotes` ahora aplica búsqueda + orden además de los filtros previos.

### Limitaciones actuales (honestas)
- No pude ejecutar `flutter analyze` ni compilar en este entorno (sin SDK de Flutter). Hice verificación estática manual (balance de llaves/paréntesis en los 40 archivos, cruce de imports relativos, cruce de parámetros de los widgets nuevos contra sus usos) — recomiendo correr `flutter analyze` como primer paso al abrir el proyecto.
- El "arrastre" del swipe no muestra las etiquetas "Me interesa"/"Descartar" en tiempo real durante el gesto (sí quedan como etiquetas de texto fijas bajo los botones) — `flutter_card_swiper` no expone el progreso del arrastre de forma sencilla sin arriesgar la mecánica que ya funciona.
- La verificación de vendedor sigue siendo un campo de demostración (no hay verificación real de identidad).
- Favoritos, solicitudes y cotizaciones no persisten entre reinicios de la app (por diseño, sigue siendo `MockStore`).
