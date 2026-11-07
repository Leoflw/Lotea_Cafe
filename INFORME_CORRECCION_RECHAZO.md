# Corrección: pantalla roja al rechazar una cotización

**Causa raíz.** En `quote_detail_screen.dart`, `_pedirTexto` creaba un `TextEditingController` local y lo liberaba (`ctrl.dispose()`) justo después del `await showDialog(...)`. Cuando `showDialog` devuelve, la ruta del diálogo sigue animando su cierre con el `TextField` montado, y al ocultarse el teclado Flutter reconstruye ese árbol varias veces. El campo leía entonces un controlador ya eliminado (`A TextEditingController was used after being disposed`), y el árbol quedó corrupto durante el desmontaje (`_dependents.isEmpty`, `wrong build scope`, y después `Duplicate GlobalKeys` y `attached`, que aparecen en cascada, sobre todo al pulsar Atrás). La escritura en Firestore ocurría después y por eso el rechazo sí se registraba.

**Cambio.** El controlador pasa a vivir en el `State` de un diálogo propio (`lib/widgets/text_prompt_dialog.dart`), que lo libera una sola vez en `dispose()`, cuando Flutter desmonta el diálogo. Además, `quote_detail_screen.dart` comprueba `mounted` tras cada diálogo antes de ejecutar la acción. No se tocaron repositorios, modelo, reglas de Firestore, ImageKit ni el indicador de mensajes sin leer.

**Archivos.** Nuevo `lib/widgets/text_prompt_dialog.dart`; modificado `lib/screens/quotes/quote_detail_screen.dart`; nueva prueba `test/text_prompt_dialog_test.dart`.

**Verificación.** No había SDK de Flutter ni red en el entorno: no se ejecutaron `flutter test`, `flutter analyze` ni las pruebas de reglas, ni se probó en dispositivo. Solo se revisó el código (flujo botón → diálogo → repositorio → transacción de Firestore → stream → rebuild) y se buscaron otros `TextEditingController` locales o `GlobalKey` duplicadas: no hay más.

**Pendiente en el teléfono.** Rechazar solicitud con y sin motivo; Cancelar y reabrir el diálogo; rechazar oferta; solicitar ajuste; Atrás después de rechazar; comprobar que el estado y el mensaje se ven en comprador y vendedor y que el indicador de no leídos sigue igual. En tu PC: `flutter pub get`, `flutter analyze`, `flutter test` (esperado: 181 + las 4 nuevas) y las 13 pruebas de reglas.
