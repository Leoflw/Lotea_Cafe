# CaféMatch — Build de pruebas (sin backend, para generar APK)

Esta versión NO usa Firebase ni ningún servidor: todo (usuarios,
perfiles, likes, matches, mensajes) vive en memoria (RAM) mientras la
app está abierta. Al cerrarla o matarla desde recientes, todo se
borra. Es exactamente para lo que la pediste: probar la funcionalidad
de las pantallas y el flujo completo, no la persistencia de datos.

Viene con **5 perfiles de café de demo precargados** para que puedas
probar el swipe sin tener que registrar vendedores primero, y un botón
de **"Entrar como comprador demo"** en el login para saltarte el
registro manual.

## 1. Requisitos en tu computador

- Flutter SDK instalado (`flutter --version` debe funcionar).
  Si no lo tienes: https://docs.flutter.dev/get-started/install
- Con Flutter se instala el Android SDK/toolchain necesario para
  compilar APKs (o puedes usar Android Studio, que lo trae integrado).
- Conexión a internet (para que `flutter pub get` descargue las
  dependencias la primera vez).

Verifica que todo esté bien configurado con:

```bash
flutter doctor
```

(Presta atención sobre todo a la sección "Android toolchain" — debe
estar en verde. No necesitas Xcode/iOS para esto.)

## 2. Generar el APK

Desde la raíz del proyecto (donde está `pubspec.yaml`):

```bash
cd cafe_match_app
flutter pub get
flutter build apk --release
```

Esto genera el archivo en:

```
build/app/outputs/flutter-apk/app-release.apk
```

Cópialo a tu teléfono (por USB, Drive, WhatsApp, lo que te sea más
fácil) y ábrelo para instalarlo. Como no viene de Play Store, Android
13 te va a pedir permiso para "instalar apps de fuentes desconocidas"
la primera vez — acéptalo solo para esta instalación de prueba.

### Alternativa aún más rápida: correrla en modo debug con el cable USB

Si tienes tu teléfono conectado por USB con la depuración activada
(Ajustes → Opciones de desarrollador → Depuración USB), puedes
saltarte generar el APK y correr la app directamente:

```bash
flutter devices        # confirma que tu teléfono aparece en la lista
flutter run             # la instala y la abre en tu teléfono
```

Esto es más rápido para iterar mientras pruebas, aunque el resultado
final que puedes compartir con otros sigue siendo el APK del paso 2.

## 3. Cómo probar el flujo completo

1. Abre la app → toca **"Entrar como comprador demo"** (o regístrate
   manualmente eligiendo el rol "Comprador").
2. En **Descubrir**, desliza las tarjetas (o usa los botones ❌ / ❤️)
   sobre los 5 perfiles de café precargados. Prueba también el ícono
   de filtros (🎚) arriba a la derecha.
3. Cuando des like a un perfil, se genera un **match** automáticamente
   y aparece el diálogo "¡Es un match!" → toca "Ir al chat" y envía
   algunos mensajes.
4. Ve a la pestaña **Matches** para ver la lista y reabrir esos chats.
5. Cierra sesión (pestaña Cuenta) y **regístrate como Vendedor** para
   probar el otro flujo: completa el formulario de perfil de café
   (fotos desde la galería del teléfono, variedades, precio, etc.) y
   publícalo.
6. Si quieres ver tu propio perfil de vendedor apareciendo en el swipe,
   necesitarías iniciar sesión con otra cuenta compradora — como todo
   vive en memoria, puedes registrar cuantas cuentas de prueba quieras
   en la misma sesión de la app.

## 4. Qué NO incluye esta build (a propósito)

- Persistencia de datos: si cierras la app, todo se reinicia (los 5
  perfiles demo se vuelven a sembrar, tus cuentas/matches/chats de
  prueba se pierden).
- Backend/red: no hay llamadas a internet, ni pagos, ni notificaciones
  push, ni subida real de imágenes (las fotos se leen directo del
  almacenamiento del teléfono).
- Multiusuario real: dos personas no pueden chatear entre sí desde dos
  teléfonos distintos, porque no hay servidor compartido — cada
  instalación tiene su propia memoria aislada.

Cuando quieras pasar a una versión con backend real (Firebase) para
pruebas multiusuario o persistencia, usamos la versión anterior del
proyecto que ya tiene toda esa integración lista.

## 5. Estructura del proyecto

```
lib/
  data/mock_store.dart   → "backend" en memoria (usuarios, perfiles, matches, chats)
  models/                → AppUser, CoffeeProfile, MatchModel, ChatMessage
  services/session_provider.dart → sesión activa del usuario
  theme/                 → paleta y estilos (AppTheme)
  screens/
    auth/                → login (con acceso rápido demo), registro
    home/                → shell con bottom navigation (según rol)
    swipe/                → feed tipo Tinder + filtros
    profile/              → edición de perfil de café / cuenta
    matches/              → lista de matches
    chat/                 → chat en tiempo real (en memoria)
  widgets/                → SwipeCard reutilizable
```
