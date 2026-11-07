# imagekit-upload-auth

Cloudflare Worker (plan gratuito) que autoriza las subidas de fotos de Lotea Café a ImageKit.
La guía completa de instalación y despliegue está en [`../../IMAGEKIT_SETUP.md`](../../IMAGEKIT_SETUP.md).

```
src/index.js      Punto de entrada: reglas de acceso, validación de la petición, respuesta
src/firebase.js   Validación criptográfica del token de Firebase (WebCrypto, sin dependencias)
src/imagekit.js   Firma HMAC-SHA1 que exige ImageKit (clave privada = secreto del Worker)
test/             26 pruebas (`npm test`), sin red
wrangler.toml     Variables públicas; la clave privada NO va aquí
```

## Contrato

`POST /` con `Authorization: Bearer <ID token de Firebase>` y cuerpo JSON:

```json
{ "purpose": "lot" | "profile", "contentType": "image/jpeg" | "image/png" | "image/webp", "size": 123456 }
```

Respuesta `200`:

```json
{ "token": "…", "expire": 1800000600, "signature": "…", "publicKey": "public_…",
  "folder": "/lotea-cafe/users/<uid>/lots", "fileName": "lot_<ms>_<id>.jpg", "maxBytes": 5242880 }
```

Errores (`{"error": "…"}`): `400` petición inválida · `401` sin sesión o token no válido · `403` rol
no permitido · `404`/`405` ruta o método · `413` demasiado grande · `415` formato no admitido ·
`429` demasiadas subidas · `503` no se pudo validar contra Firebase.

## Comandos

```bash
npm install
npm test
npx wrangler secret put IMAGEKIT_PRIVATE_KEY   # solo secreto; nunca en archivos
npx wrangler deploy
```
