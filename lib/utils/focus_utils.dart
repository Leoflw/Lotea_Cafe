import 'package:flutter/widgets.dart';

/// Libera el foco de teclado. Se usa ANTES de navegar, abrir/cerrar modales
/// o cerrar pantallas con campos de texto, para que Flutter no restaure el
/// foco (y con él el teclado) al volver a la ruta anterior.
/// No es un parche aislado: la causa raíz del teclado "fantasma" en Descubrir
/// se resolvió sacando el TextField de esa pantalla (ver SearchScreen).
void liberarFoco() => FocusManager.instance.primaryFocus?.unfocus();
