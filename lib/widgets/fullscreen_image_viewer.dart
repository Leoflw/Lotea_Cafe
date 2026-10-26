import 'dart:io';
import 'package:flutter/material.dart';

/// Visor de imágenes a pantalla completa, reutilizable en toda la app
/// (perfil de vendedor, galería, detalle del café, guardados, etc.).
/// Soporta zoom con pellizco, swipe entre varias imágenes, cierre con X
/// y cierre deslizando hacia abajo.
class FullscreenImageViewer extends StatefulWidget {
  final List<String> imagenes; // rutas locales
  final int indiceInicial;

  const FullscreenImageViewer({super.key, required this.imagenes, this.indiceInicial = 0});

  /// Punto de entrada único: abre el visor sobre [images], empezando
  /// exactamente en [initialIndex].
  static Future<void> abrir(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            FullscreenImageViewer(imagenes: images, indiceInicial: initialIndex.clamp(0, images.length - 1)),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final PageController _pageController = PageController(initialPage: widget.indiceInicial);
  late int _indiceActual = widget.indiceInicial;
  double _arrastreVertical = 0;
  bool _cerrando = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _cerrar() {
    if (!_cerrando) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final opacidadFondo = (1 - (_arrastreVertical.abs() / 400)).clamp(0.0, 1.0);

    return GestureDetector(
      onVerticalDragUpdate: (details) => setState(() => _arrastreVertical += details.delta.dy),
      onVerticalDragEnd: (details) {
        if (_arrastreVertical.abs() > 120) {
          _cerrando = true;
          _cerrar();
        } else {
          setState(() => _arrastreVertical = 0);
        }
      },
      child: Container(
        color: Colors.black.withOpacity(opacidadFondo),
        child: Transform.translate(
          offset: Offset(0, _arrastreVertical),
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.imagenes.length,
                onPageChanged: (i) => setState(() => _indiceActual = i),
                itemBuilder: (context, i) {
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(
                        File(widget.imagenes[i]),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white38,
                          size: 64,
                        ),
                      ),
                    ),
                  );
                },
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
                          tooltip: 'Cerrar',
                          onPressed: _cerrar,
                        ),
                        if (widget.imagenes.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_indiceActual + 1} / ${widget.imagenes.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        const SizedBox(width: 40),
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
