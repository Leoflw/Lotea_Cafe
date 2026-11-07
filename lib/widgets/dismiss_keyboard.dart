import 'package:flutter/material.dart';
import '../utils/focus_utils.dart';

/// Envuelve pantallas con formularios: tocar fuera de un campo cierra el
/// teclado, y arrastrar la lista también. Evita teclados que se quedan
/// abiertos tapando el contenido.
class DismissKeyboard extends StatelessWidget {
  final Widget child;
  const DismissKeyboard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: liberarFoco,
      child: child,
    );
  }
}
