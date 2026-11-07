import 'package:flutter/material.dart';

/// Una imagen con zoom y desplazamiento, con SU PROPIO estado de
/// transformación (cada página del visor tiene una instancia, así una imagen
/// nunca hereda el zoom de otra).
///
/// Reglas de interacción (corrección del visor original):
///  - 1x: la imagen queda centrada y NO se puede arrastrar (`panEnabled` es
///    falso); solo se puede hacer pinch para ampliar o doble toque.
///  - >1x: el pan se activa y queda limitado a los bordes (boundaryMargin
///    cero), de modo que la imagen no puede salirse de la pantalla.
///  - El estado (escala + traslación) vive únicamente en el
///    [TransformationController]; ningún GestureDetector externo desplaza la
///    imagen, por lo que no hay "rebote al centro".
///  - Doble toque: 1x → 2.5x (centrado en el punto tocado) → 1x, animado.
class ZoomableImage extends StatefulWidget {
  final ImageProvider imagen;
  final String etiquetaSemantica;

  /// Notifica al visor cuando la imagen pasa a estar ampliada o vuelve a 1x,
  /// para que este habilite/deshabilite el cierre por gesto vertical y el
  /// cambio de página.
  final ValueChanged<bool>? onZoomChanged;

  const ZoomableImage({
    super.key,
    required this.imagen,
    required this.etiquetaSemantica,
    this.onZoomChanged,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> with SingleTickerProviderStateMixin {
  static const double _zoomMaximo = 4.0;
  static const double _zoomDobleToque = 2.5;
  static const double _umbralAmpliada = 1.02;

  final TransformationController _controller = TransformationController();
  late final AnimationController _animacion =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Animation<Matrix4>? _animMatriz;

  bool _ampliada = false;
  Size _viewport = Size.zero;
  Offset _posicionDobleToque = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_alCambiarTransformacion);
    _animacion.addListener(() {
      final m = _animMatriz;
      if (m != null) _controller.value = m.value;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_alCambiarTransformacion);
    _controller.dispose();
    _animacion.dispose();
    super.dispose();
  }

  double get _escala => _controller.value.getMaxScaleOnAxis();

  void _alCambiarTransformacion() {
    final ampliada = _escala > _umbralAmpliada;
    if (ampliada != _ampliada) {
      setState(() => _ampliada = ampliada);
      widget.onZoomChanged?.call(ampliada);
    }
  }

  void _animarHacia(Matrix4 destino) {
    _animMatriz = Matrix4Tween(begin: _controller.value, end: destino).animate(
      CurvedAnimation(parent: _animacion, curve: Curves.easeOutCubic),
    );
    _animacion.forward(from: 0);
  }

  Matrix4 _matrizZoom(double escala, Offset foco) {
    // Mantiene bajo el dedo el punto tocado y limita la traslación para que
    // la imagen no salga del área visible.
    final tx = (-foco.dx * (escala - 1)).clamp(_viewport.width * (1 - escala), 0.0).toDouble();
    final ty = (-foco.dy * (escala - 1)).clamp(_viewport.height * (1 - escala), 0.0).toDouble();
    return Matrix4.identity()
      ..setEntry(0, 0, escala)
      ..setEntry(1, 1, escala)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  void _dobleToque() {
    if (_ampliada) {
      _animarHacia(Matrix4.identity());
    } else {
      _animarHacia(_matrizZoom(_zoomDobleToque, _posicionDobleToque));
    }
  }

  void _restablecer() => _animarHacia(Matrix4.identity());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onDoubleTapDown: (d) => _posicionDobleToque = d.localPosition,
              onDoubleTap: _dobleToque,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1.0,
                maxScale: _zoomMaximo,
                // Pan solo cuando hay zoom: a 1x la imagen no se arrastra.
                panEnabled: _ampliada,
                scaleEnabled: true,
                boundaryMargin: EdgeInsets.zero,
                child: Semantics(
                  label: widget.etiquetaSemantica,
                  image: true,
                  child: Center(
                    child: Image(
                      image: widget.imagen,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white38,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_ampliada)
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'Restablecer zoom a 1x',
                      child: Material(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _restablecer,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                                SizedBox(width: 8),
                                Text('Restablecer · 1x', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
