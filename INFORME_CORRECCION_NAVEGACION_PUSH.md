# Informe v5.1: fallos de `test/push_navigation_test.dart`

## Qué se ejecutó y qué no
En este entorno NO hay Flutter ni Dart y no hay red. **No ejecuté** `flutter test test/push_navigation_test.dart`,
`flutter test` ni `flutter analyze`. No afirmo que pasen. Todo lo de abajo es análisis estático del código.
Resultados reales previos (los tuyos, v5): pub get ok; analyze 40 avisos informativos; flutter test 5 fallos.

## Causa raíz
**Fallo 5 («Ver»)** — problema del test, causa bien respaldada por tu traza (y=624 con alto 600):
el reloj del test avanza antes de construir el primer fotograma, así que el SnackBar se construye con la
animación en 0, aún fuera de pantalla bajo el borde inferior. El toque caía fuera, no ocurría y no había navegación.

**Fallos 1–4 (la pantalla destino no aparece)** — la producción comprueba sesión, uid y acceso correctamente.
Diagnóstico más probable, NO verificado: la misma sincronización (`pump()` + `pump(400ms)`) no asienta la
transición de la ruta empujada tras el microtask del stream y el resolver. El resolver sí se ejecuta
(las pruebas de «sin acceso»/error, que usan la misma cadena, no fallan). Si tras este cambio alguno sigue
fallando, la aserción `canPop()` que añadí en la prueba 1 distingue «no se empujó la ruta» de «se empujó pero no se ve».

**Fallo real de producción encontrado (no era causa de los cinco):** en `PushCoordinator._intentar`, un destino
que llegaba mientras otro se resolvía quedaba pendiente (`_navegando` activo) y nunca se reintentaba al terminar:
se perdía hasta el siguiente cambio de sesión. Corregido.

## Archivos modificados
- `lib/services/push_navigation.dart`: en el `finally` de `_intentar`, si hay `_pendiente` se reintenta. Se conservan
  la comprobación de sesión, de `uid` actual (`_uid != uid`) y de acceso (resolver) antes de navegar.
- `test/push_navigation_test.dart`:
  - `_asentar` usa `pump()` + `pumpAndSettle()` (transiciones y SnackBar terminan de entrar).
  - «Ver»: comprueba que está dentro del área visible y es `hitTestable`, y toca realmente (sin `warnIfMissed: false`).
  - Prueba 1: añade `canPop()` para confirmar que la ruta se apila.
  - Nuevas: segunda notificación durante la resolución no se pierde; cambio de cuenta durante la comprobación no abre el destino.
- Nuevo: este informe. No se tocó ImageKit, Worker, reglas de Firestore ni repositorios.

## Pendiente de tu lado
`flutter test test/push_navigation_test.dart`, `flutter test`, `flutter analyze`. Cuéntame el resultado exacto.
