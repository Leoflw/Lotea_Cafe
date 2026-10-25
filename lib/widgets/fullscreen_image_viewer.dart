import 'package:flutter/material.dart';
import '../utils/image_source.dart';
import 'zoomable_image.dart';

/// Visor de imágenes a pantalla completa, reutilizable en toda la app.
///
/// Arquitectura de gestos (corrige el conflicto zoom/pan/cierre de la versión
/// anterior, donde un GestureDetector vertical desplazaba TODO el contenido):
///  - Zoom, pan y doble toque viven dentro de [ZoomableImage] (una instancia
///    con su propio TransformationController por página).
///  - Este widget solo decide dos cosas según el estado de zoom que le reporta
///    la página actual:
///      * cambio de página: deshabilitado mientras la imagen está ampliada
///        (así el arrastre horizontal mueve la imagen, no el PageView);
///      * cierre por gesto vertical: solo a 1x y con UN dedo. No desplaza la
///        imagen (a 1x debe permanecer centrada); solo atenúa el fondo y
///        cierra al superar un umbral.
class FullscreenImageViewer extends StatefulWidget {
  final List<String> imagenes;
  final int indiceInicial;

  const FullscreenImageViewer({super.key, required this.imagenes, this.indiceInicial = 0});

  /// Punto de entrada único: abre el visor sobre [images] empezando en
  /// [initialIndex]. Al cerrar, vuelve exactamente a la pantalla anterior.
  static Future<void> abrir(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => FullscreenImageViewer(
          imagenes: images,
          indiceInicial: initialIndex.clamp(0, images.length - 1),
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  static const double _umbralCierre = 110;
  static const double _velocidadCierre = 900;

  late final PageController _pageController = PageController(initialPage: widget.indiceInicial);
  late int _indiceActual = widget.indiceInicial;

  bool _ampliada = false;
  double _arrastreVertical = 0;
  int _punteros = 0;
  bool _huboMultitouch = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _cerrar() => Navigator.of(context).maybePop();

  void _alZoomCambiado(bool ampliada) {
    setState(() {
      _ampliada = ampliada;
      if (ampliada) _arrastreVertical = 0;
    });
  }

  void _alCambiarPagina(int i) {
    setState(() {
      _indiceActual = i;
      _ampliada = false; // la página nueva siempre abre en 1x
      _arrastreVertical = 0;
    });
  }

  void _arrastreActualizado(DragUpdateDetails d) {
    if (_huboMultitouch || _ampliada) return;
    setState(() => _arrastreVertical += d.delta.dy);
  }

  void _arrastreTerminado(DragEndDetails d) {
    final velocidad = d.primaryVelocity ?? 0;
    final cerrar = !_huboMultitouch &&
        !_ampliada &&
        (_arrastreVertical.abs() > _umbralCierre || velocidad.abs() > _velocidadCierre);
    if (cerrar) {
      _cerrar();
    } else {
      setState(() => _arrastreVertical = 0);
    }
  }

  void _punteroAbajo(PointerDownEvent _) {
    _punteros++;
    if (_punteros > 1) _huboMultitouch = true;
  }

  void _punteroArriba(PointerEvent _) {
    _punteros = (_punteros - 1).clamp(0, 10).toInt();
    if (_punteros == 0) _huboMultitouch = false;
  }

  @override
  Widget build(BuildContext context) {
    // El fondo se atenúa con el arrastre; la imagen NO se mueve.
    final opacidadFondo = (1 - (_arrastreVertical.abs() / 420)).clamp(0.35, 1.0).toDouble();
    final total = widget.imagenes.length;

    return Listener(
      onPointerDown: _punteroAbajo,
      onPointerUp: _punteroArriba,
      onPointerCancel: _punteroArriba,
      child: GestureDetector(
        // Sin handlers cuando está ampliada: no se registra el reconocedor
        // vertical y no compite con el pan de la imagen.
        onVerticalDragUpdate: _ampliada ? null : _arrastreActualizado,
        onVerticalDragEnd: _ampliada ? null : _arrastreTerminado,
        child: Container(
          color: Colors.black.withOpacity(opacidadFondo),
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: total,
                physics: _ampliada ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                onPageChanged: _alCambiarPagina,
                itemBuilder: (context, i) => ZoomableImage(
                  key: ValueKey('zoom_${widget.imagenes[i]}_$i'),
                  imagen: imageProviderFor(widget.imagenes[i], anchoPx: 1600),
                  etiquetaSemantica: 'Fotografía ${i + 1} de $total',
                  onZoomChanged: i == _indiceActual ? _alZoomCambiado : null,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Cerrar galería',
                          iconSize: 26,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black38,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _cerrar,
                        ),
                        if (total > 1)
                          Semantics(
                            label: 'Fotografía ${_indiceActual + 1} de $total',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '${_indiceActual + 1} / $total',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                          ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
