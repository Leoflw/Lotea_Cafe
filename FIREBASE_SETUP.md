# Configurar Firebase para Lotea Café

Esta guía lleva el proyecto de «código listo» a «app conectada a Firebase».
Los pasos 1–2, 4–8 y 10 los haces tú en Firebase Console/terminal: **nada de
esto se ha ejecutado por ti**, y no hay ningún dato de proyecto inventado en
el código.

> **Estado del repositorio:** la carpeta `android/` **no existe todavía**
> (el proyecto recibido solo traía `lib/`, `pubspec.yaml` y recursos). Hay que
> generarla en el paso 3.

## Requisitos

- Flutter estable reciente y Dart ≥ 3.3.
- Node.js (para Firebase CLI) y una cuenta de Google.
- CLI: `npm install -g firebase-tools` y `dart pub global activate flutterfire_cli`.
- Iniciar sesión: `firebase login`.

## Paso 1. Crear o elegir el proyecto en Firebase

En <https://console.firebase.google.com> crea un proyecto (p. ej. «Lotea Café»)
o elige uno existente. Anota el **ID del proyecto**; lo usarás en el paso 5.

## Paso 2. Decidir el identificador de paquete (applicationId)

**Decisión que te corresponde a ti.** Una vez registrada la app en Firebase y
publicada en una tienda, el identificador no se puede cambiar sin crear otra
app. Usa un dominio que controles, en minúsculas, por ejemplo
`co.tudominio.loteacafe`. En esta guía lo llamamos `TU_ID_DE_PAQUETE`.

## Paso 3. Generar la carpeta `android/` y aplicar la marca

Desde la raíz del proyecto:

```bash
flutter create . --platforms=android --org co.tudominio --project-name lotea_cafe
flutter pub get
```

Con `--org co.tudominio` y el nombre `lotea_cafe`, el `applicationId`
resultante es `co.tudominio.lotea_cafe`. Si prefieres otro, edítalo en
`android/app/build.gradle(.kts)` **antes** de registrar la app en Firebase.

Nombre visible de la app: ya está configurado. `AndroidManifest.xml` usa
`@string/app_name`, definido como `Lotea Café` en
`android/app/src/main/res/values/strings.xml`. Si vuelves a ejecutar
`flutter create` sobre un proyecto nuevo, repite ese cambio.

Icono de la app (usa `assets/branding/`; los recursos ya generados viven en
`android/app/src/main/res/`):

```bash
dart run flutter_launcher_icons
```

> **Nota sobre el icono:** el símbolo se recortó de la imagen de presentación
> de marca (raster), por lo que no es tan nítido como un original vectorial.
> Para publicar en la tienda, pídele al diseñador el símbolo en SVG/PNG de
> 1024 px y reemplaza `lotea_cafe_icon.png`, `lotea_cafe_icon_foreground.png`
> y `lotea_cafe_symbol.png`.

## Paso 4. Registrar la app Android y conectar con FlutterFire

```bash
flutterfire configure --project=TU_ID_DE_PROYECTO --platforms=android --android-id=TU_ID_DE_PAQUETE
```


Esto descarga `android/app/google-services.json` y genera
`lib/firebase_options.dart`.

**Ambos archivos son necesarios para esta implementación:**

- `google-services.json` proporciona la configuración nativa de Android mediante el plugin de Google Services.
- `firebase_options.dart` contiene las opciones utilizadas por `FirebaseBootstrap` al inicializar Firebase.

Ambos archivos están excluidos de Git porque cada entorno debe generar su propia configuración.

Para configurar una instalación nueva, ejecuta:

```bash
flutterfire configure --project=TU_ID_DE_PROYECTO --platforms=android --android-id=TU_ID_DE_PAQUETE
```

No elimines estos archivos de tu entorno local. Tampoco debes confundirlos con las claves privadas de cuentas de servicio de Google, que nunca deben publicarse.


Huella SHA para futuras funciones (Google Sign-In, etc.; no se usa hoy):
`cd android && ./gradlew signingReport`.

## Paso 5. Vincular la CLI al proyecto

Crea `.firebaserc` (no se incluye porque contiene tu ID de proyecto):

```json
{ "projects": { "default": "TU_ID_DE_PROYECTO" } }
```

`firebase.json` referencia `firestore.rules` y `firestore.indexes.json`. Ya no
referencia `storage.rules`: las fotos van a ImageKit (paso 9).

## Paso 6. Activar Firestore

Consola → **Build → Firestore Database → Create database**. Elige el modo
**producción** (las reglas se publican en el paso 8) y una ubicación cercana
a tus usuarios (para Colombia suele elegirse `southamerica-east1` o `us-east1`).
La ubicación no se puede cambiar después.

## Paso 7. Activar Authentication (correo y contraseña)

Consola → **Build → Authentication → Get started → Sign-in method →
Email/Password → Enable**. Sin esto, el registro y el login muestran
«configuración pendiente».

La verificación de correo está soportada por el código (`AuthRepository`) pero
no se exige para entrar; actívala en tu flujo cuando lo decidas.

## Paso 8. Publicar reglas de seguridad

```bash
firebase deploy --only firestore:rules
```

Revisa `firestore.rules` antes de publicar: es el contrato de seguridad de la
app (roles, propiedad de datos, transiciones de cotización). Las reglas **no
han sido ejecutadas contra el emulador** en esta entrega (ver README, sección
«Qué falta verificar»).

## Paso 9. Fotos (ImageKit + Cloudflare Worker)

Las fotos **no usan Cloud Storage for Firebase**, así que **no necesitas el
plan Blaze**. Se alojan en ImageKit (plan gratuito) y un Cloudflare Worker
gratuito autoriza cada subida. Sigue **[IMAGEKIT_SETUP.md](IMAGEKIT_SETUP.md)**.

## Paso 10. Publicar índices

```bash
firebase deploy --only firestore:indexes
```

Los índices tardan unos minutos en construirse. Si una consulta falla con
«falta un índice», la app muestra «Configuración pendiente» en lugar de una
lista vacía; la consola de Firebase también ofrece un enlace directo.

## Paso 11. Probar con el emulador (recomendado antes de producción)

```bash
firebase emulators:start --only auth,firestore
```

y apunta la app al emulador (`useFirestoreEmulator`, `useAuthEmulator`) **solo en depuración**. Esta entrega no incluye ese
cableado para no mezclar configuración de desarrollo con la de producción.

## Paso 12. Ejecutar

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define-from-file=env.json   # valores de ImageKit (paso 9)
```

## Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| Pantalla «Falta conectar Firebase» | Falta `google-services.json` o el plugin Gradle (pasos 3–4). |
| «El acceso con correo y contraseña no está activado» | Paso 7. |
| «No tienes permiso para realizar esta acción» | Reglas no publicadas o desactualizadas (paso 8). |
| «Falta un índice de Firestore» | Paso 10. |
| «La subida de fotos no está configurada todavía» | Paso 9: faltan los `--dart-define` de ImageKit (IMAGEKIT_SETUP.md). |
| El catálogo está vacío | Aún no hay lotes **publicados**; un vendedor debe crear su perfil y publicar. |

## Fuera de alcance de esta ronda

- iOS (no se generó la carpeta `ios/`).
- Pagos, pedidos, logística. (Las notificaciones push se explican en PUSH_NOTIFICATIONS.md.)
- Verificación real de vendedores y calificaciones (los campos existen pero
  solo los puede escribir un proceso de administración, no la app).
