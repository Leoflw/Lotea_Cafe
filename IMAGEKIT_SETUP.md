# Fotos con ImageKit + Cloudflare Worker (sin plan Blaze)

Lotea Café guarda ahora sus fotos (perfil, finca/galería y lotes de café) en
**ImageKit** (plan gratuito). Firebase sigue siendo el backend: **Authentication**
y **Firestore** no cambian. **Cloud Storage for Firebase ya no se usa**, así que
no necesitas activar el plan Blaze.

```
 Teléfono (Flutter)                Cloudflare Worker (gratis)              ImageKit
 ───────────────────               ───────────────────────────             ────────
 1. elegir foto + comprimir
 2. validar tipo y tamaño
 3. POST  Authorization: Bearer <token de Firebase>  ─────►  valida el token (firma, proyecto,
                                                            emisor, expiración, UID)
                                                            lee users/{uid}.rol en Firestore
                                                            comprueba rol, tipo y tamaño
    ◄── token + expire + signature + folder + fileName ───  firma con la clave PRIVADA (secreto)
 4. POST multipart/form-data (HTTPS) ──────────────────────────────────────────────► guarda la foto
    ◄──────────────────────────────── url + fileId ─────────────────────────────────
 5. guardar url + fileId en Firestore
```

## 1. Qué está implementado y qué te toca hacer

### Implementado en el ZIP

- Subida a ImageKit por HTTPS `multipart/form-data` (`lib/repositories/image_repository.dart`).
- Compresión al elegir la foto (lado máx. 1600 px, calidad 80), validación de
  tipo por contenido (JPEG, PNG, WebP) y de tamaño (máx. 5 MB) en el teléfono y en el Worker.
- Estados de carga, mensajes de error y reintentos (automáticos ante fallos de
  red y botón «Reintentar»).
- Borradores sin foto; publicar exige al menos una foto subida con éxito
  (en la pantalla **y** en `CoffeeLotRepository`). Una foto cuya subida falló nunca se
  guarda como si estuviera disponible.
- Visualización: `AppImage` y el visor existentes, pidiendo a ImageKit el tamaño que se pinta.
- Código del Worker en `cloudflare/imagekit-upload-auth/` (con 26 pruebas).
- Se retiró `firebase_storage` (ningún archivo la necesitaba ya) y el bloque `storage` de `firebase.json`.
- Pruebas de Flutter y documentación.

### Pasos manuales (los haces tú)

1. Crear la cuenta de ImageKit y copiar el **URL endpoint**, la **public key** y la **private key**.
2. Desplegar el Worker y guardar la **private key** como **secreto** (solo en Cloudflare).
3. Poner la URL del Worker y la public key en `env.json` y compilar con `--dart-define-from-file`.
4. Probar una subida desde el teléfono.

> **Nunca** pegues la private key en el chat, en Dart, en `wrangler.toml`, en
> Firestore ni en el ZIP. La app solo necesita datos públicos.

## 2. ImageKit: obtener el endpoint y las claves

1. Crea una cuenta gratuita en <https://imagekit.io> y entra al panel.
2. Ve a **Developer options** (opciones de desarrollador) y copia:
   - **URL endpoint** → `https://ik.imagekit.io/TU_ID`
   - **Public key** → `public_…`
   - **Private key** → `private_…` (solo para el paso 3; no la compartas)
3. Revisa en tu panel los límites del plan gratuito (almacenamiento y ancho de
   banda) para saber cuántas fotos caben. Los nombres de menús pueden variar un poco.

Las carpetas se crean solas: `/lotea-cafe/users/{uid}/lots` y `/lotea-cafe/users/{uid}/profile`.

## 3. Cloudflare Worker (plan gratuito)

Requisitos: cuenta gratuita de Cloudflare y Node.js 20 o superior.

```bash
cd cloudflare/imagekit-upload-auth
npm install                 # instala wrangler (CLI de Cloudflare)
npm test                    # (opcional) 26 pruebas del Worker, sin red
npx wrangler login          # abre el navegador para autorizar
```

Edita `wrangler.toml` y cambia solo estas variables **públicas**:

| Variable | Valor |
|---|---|
| `FIREBASE_PROJECT_ID` | `lotea-cafe` (ya está; es el de `.firebaserc`) |
| `IMAGEKIT_PUBLIC_KEY` | tu public key (`public_…`) |
| `IMAGEKIT_FOLDER_ROOT` | `/lotea-cafe` (déjalo así) |

Guarda la clave privada como **secreto** (te la pedirá por teclado, no queda en ningún archivo):

```bash
npx wrangler secret put IMAGEKIT_PRIVATE_KEY
```

También puedes hacerlo desde el panel: **Workers & Pages → imagekit-upload-auth →
Settings → Variables and Secrets → Add → tipo *Secret*** con el nombre
`IMAGEKIT_PRIVATE_KEY`. (Si prefieres crear el secreto desde el panel antes del
primer despliegue, hazlo después de `wrangler deploy`, que crea el Worker.)

Despliega:

```bash
npx wrangler deploy
```

Al terminar muestra la URL, parecida a
`https://imagekit-upload-auth.TU-SUBDOMINIO.workers.dev`. Esa es tu **URL del endpoint**.

Comprobación rápida (sin sesión debe rechazar):

```bash
curl -i -X POST https://imagekit-upload-auth.TU-SUBDOMINIO.workers.dev/
# → HTTP/2 401   {"error":"Falta el token de sesión."}
```

El plan gratuito de Workers permite un número diario de peticiones; revisa el
límite vigente en tu panel de Cloudflare. Una subida usa 1 petición al Worker.

### Variables del Worker

| Nombre | Tipo | Para qué |
|---|---|---|
| `FIREBASE_PROJECT_ID` | variable | El Worker solo acepta tokens de este proyecto. |
| `IMAGEKIT_PUBLIC_KEY` | variable | Se devuelve a la app junto con la firma. |
| `IMAGEKIT_FOLDER_ROOT` | variable | Carpeta raíz en ImageKit. |
| `IMAGEKIT_PRIVATE_KEY` | **secreto** | Firma HMAC-SHA1 de cada autorización. Nunca sale del Worker. |
| `ALLOW_HTTP` | solo local | `true` únicamente en `wrangler dev`; no lo definas en producción. |

Para probar el Worker en tu computador (opcional): copia `.dev.vars.example` a
`.dev.vars` (está en `.gitignore`) con valores propios y ejecuta `npx wrangler dev`.

## 4. Configurar la app

```bash
cp env.example.json env.json      # env.json está en .gitignore
```

```json
{
  "IMAGEKIT_AUTH_ENDPOINT": "https://imagekit-upload-auth.TU-SUBDOMINIO.workers.dev",
  "IMAGEKIT_PUBLIC_KEY": "public_…",
  "IMAGEKIT_URL_ENDPOINT": "https://ik.imagekit.io/TU_ID"
}
```

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
flutter build apk --dart-define-from-file=env.json     # para instalar en el teléfono
```

Los tres valores son públicos. `IMAGEKIT_URL_ENDPOINT` es opcional (solo sirve
para reconocer dominios propios al optimizar la visualización).

Si falta `IMAGEKIT_AUTH_ENDPOINT` o `IMAGEKIT_PUBLIC_KEY`, o el endpoint no es
`https://`, la app muestra «La subida de fotos no está configurada todavía».

## 5. Probar una subida desde el teléfono (Samsung A32)

1. Instala la APK compilada con `--dart-define-from-file=env.json` y entra con una cuenta **vendedor**.
2. **Perfil de mi marca** → toca el círculo de la foto → elige una imagen → **Guardar perfil**.
   Debe mostrar «Subiendo foto principal…» y luego «Perfil de vendedor actualizado».
3. **Nuevo café** → agrega fotos → **Guardar como borrador** (también sin fotos) y luego **Publicar café**.
4. En ImageKit → **Media library** debe aparecer `lotea-cafe/users/<uid>/lots/…`.
5. Entra con otra cuenta (comprador) en otro teléfono o emulador: el café publicado debe verse con su foto.
6. Modo avión + guardar un borrador con una foto nueva: debe guardar el borrador, marcar la foto
   «No subida» y ofrecer «Reintentar»; al reconectar y reintentar, sube sola. Publicar en ese
   estado debe bloquearse con un mensaje.
7. Entra con una cuenta **comprador**: no tiene pantallas para subir fotos (y, si se forzara,
   el Worker respondería 403).

## 6. Qué se guarda en Firestore (esquema)

No hay campos nuevos: se conservan los existentes para no tocar las reglas de Firestore.

| Documento | Campo | Contenido ahora |
|---|---|---|
| `coffeeLots/{id}` | `fotos` | URLs públicas de ImageKit (solo fotos subidas con éxito) |
| `coffeeLots/{id}` | `fotosStoragePaths` | `fileId` de ImageKit de cada foto, misma posición que `fotos` |
| `sellerProfiles/{uid}` | `fotoPrincipal`, `galeria` | URLs públicas de ImageKit |
| `sellerProfiles/{uid}` | `fotoPrincipalStoragePath`, `galeriaStoragePaths` | `fileId` de ImageKit |

> El nombre `…StoragePaths` es histórico; ahora contiene `fileId`. Guardarlo
> permite borrar la foto más adelante. **Nunca** se guardan bytes ni Base64.

## 7. Seguridad: qué garantiza y qué no

**El Worker garantiza**

- Solo atiende `POST` por HTTPS y exige `Authorization: Bearer <token de Firebase>`.
- Valida el token criptográficamente (firma RS256 con las claves públicas de Google,
  `kid`, `exp`, `iat`, `aud` = tu proyecto, `iss`, `sub`/UID, `auth_time`).
- El UID sale **del token**; nunca de un dato enviado por el cliente.
- Lee `users/{uid}.rol` en Firestore **con el propio token del usuario** (las reglas de
  Firestore siguen mandando) y exige rol `vendedor` para fotos de lotes y de perfil.
- Rechaza tipos que no sean JPEG/PNG/WebP y tamaños de 0 o de más de 5 MB.
- La carpeta de destino se construye con el UID verificado.
- Cada autorización lleva un token único (UUID) y expira a los 10 minutos.
- Freno de abuso de mejor esfuerzo: 30 autorizaciones cada 10 minutos por usuario
  (en memoria de cada instancia del Worker; no es un límite global).

**Limitación de ImageKit que debes conocer.** La firma de ImageKit cubre solo
`token` y `expire`. No cubre la carpeta, el tamaño ni el tipo. Por eso un usuario
**con sesión de vendedor válida** y con conocimientos técnicos podría usar una
autorización para subir un archivo distinto del que declaró, o a otra carpeta, dentro de su ventana de 10 minutos.
El Worker limita lo que puede limitar (quién, cuándo, cuántas veces y qué declara), pero
no puede forzar el tamaño real del archivo. Si en el futuro necesitas garantía estricta,
la alternativa es que el Worker reciba el archivo y lo reenvíe él mismo a ImageKit (el
Worker pasa a ser un proxy de subida); no se hizo así porque pediste un endpoint de autorización.

**Fotos públicas.** Las URLs de ImageKit son públicas: cualquiera que tenga el enlace
puede ver la foto. Está bien para el catálogo, pero **no uses este mecanismo para
documentos privados o sensibles** (cédulas, RUT, contratos…).

**Fotos huérfanas.** Quitar o reemplazar una foto no la borra de ImageKit (borrar
exige la clave privada y no se añadió un endpoint de borrado). Quedan ocupando
espacio; puedes limpiarlas desde el panel de ImageKit usando el `fileId`.

**Rotar claves.** Si crees que la private key se expuso: regénérala en ImageKit y
vuelve a ejecutar `npx wrangler secret put IMAGEKIT_PRIVATE_KEY`. No hay que tocar la app.

## 8. Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| «La subida de fotos no está configurada todavía» | Compilaste sin `--dart-define-from-file=env.json` o falta alguno de los valores. |
| «Tu sesión expiró» (401) | Token de Firebase no válido para este Worker: revisa que `FIREBASE_PROJECT_ID` sea `lotea-cafe`. |
| «Solo las cuentas de vendedor…» (403) | La cuenta es compradora, o no existe `users/{uid}` en Firestore. |
| «El Worker no está configurado» (500) | Falta el secreto `IMAGEKIT_PRIVATE_KEY` o alguna variable. |
| «No se pudo subir la imagen (código 401/403)» (ImageKit) | Public key distinta de la private key guardada (deben ser del mismo par), o reloj del teléfono muy desfasado. |
| «El servicio de imágenes está ocupado» | 429 o 5xx; la app ya reintentó 3 veces. Usa «Reintentar». |
| La foto se sube pero no se ve | Revisa que la URL guardada empiece por `https://ik.imagekit.io/` y que el INTERNET del dispositivo funcione. |

## 9. Cómo se verificó esto

- **Worker:** 26 pruebas con `node --test` (token válido, expirado, de otro proyecto, firma falsa,
  UID ignorado del cuerpo, rol comprador, tipos y tamaños, HTTPS, límite de uso). **Ejecutadas y pasan.**
- **Flutter:** pruebas escritas para validación, autorización, rechazo sin sesión, fallos de red,
  persistencia en Firestore (con `fake_cloud_firestore`), catálogo, borradores y publicación.
  **No se ejecutaron** (no había Flutter SDK disponible): ejecuta `flutter pub get && flutter analyze && flutter test`.
- **No probado con servicios reales:** la subida real a ImageKit y el despliegue en Cloudflare
  dependen de tus cuentas y claves; el recorrido del paso 5 es la verificación pendiente.
