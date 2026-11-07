import 'package:flutter/material.dart';

/// Punto de «mensaje nuevo» sobre [child] (el icono de chat de una conexión o
/// la pestaña «Conexiones»). Solo se pinta cuando [visible] es true; lo decide
/// `InterestRequest.tieneMensajesNoLeidos`, no esta clase.
class IndicadorNoLeido extends StatelessWidget {
  final bool visible;
  final Widget child;

  /// Texto accesible cuando el punto es visible. Por defecto el de los
  /// mensajes; otras pestañas (solicitudes por responder, cotizaciones con
  /// oferta pendiente) indican su propio motivo. Sigue siendo un punto, no un
  /// contador.
  final String etiqueta;

  const IndicadorNoLeido({super.key, required this.visible, required this.child, this.etiqueta = 'Mensajes nuevos'});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: visible ? etiqueta : null,
      child: Badge(isLabelVisible: visible, smallSize: 10, child: child),
    );
  }
}
