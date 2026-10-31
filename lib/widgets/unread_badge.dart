import 'package:flutter/material.dart';

/// Punto de «mensaje nuevo» sobre [child] (el icono de chat de una conexión o
/// la pestaña «Conexiones»). Solo se pinta cuando [visible] es true; lo decide
/// `InterestRequest.tieneMensajesNoLeidos`, no esta clase.
class IndicadorNoLeido extends StatelessWidget {
  final bool visible;
  final Widget child;

  const IndicadorNoLeido({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: visible ? 'Mensajes nuevos' : null,
      child: Badge(isLabelVisible: visible, smallSize: 10, child: child),
    );
  }
}
