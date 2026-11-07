import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';
import 'status_pill.dart';

bool _esRemota(String ruta) => ruta.startsWith('http://') || ruta.startsWith('https://');

/// Administración de fotografías en cuadrícula de tres columnas, común al
/// formulario del café y a la galería de marca. Cada foto indica con una
/// píldora si YA ESTÁ SUBIDA (URL remota) o sigue solo en el teléfono
/// (por subir / subiendo / no subida). No decide ninguna regla: los límites,
/// la subida y la publicación siguen en las pantallas que la usan.
///
/// * [conPortada]: la primera foto es la portada (café); las demás ofrecen
///   «Hacer principal» si se pasa [onHacerPrincipal].
/// * [lleno]: oculta la casilla «Agregar» (límite alcanzado).
class PhotoGrid extends StatelessWidget {
  final List<String> fotos;
  final Set<String> fallidas;
  final bool lleno;
  final bool ocupado;
  final bool eligiendo;
  final bool conPortada;
  final VoidCallback onAgregar;
  final ValueChanged<int> onQuitar;
  final ValueChanged<int>? onHacerPrincipal;

  const PhotoGrid({
    super.key,
    required this.fotos,
    required this.lleno,
    required this.onAgregar,
    required this.onQuitar,
    this.fallidas = const {},
    this.ocupado = false,
    this.eligiendo = false,
    this.conPortada = false,
    this.onHacerPrincipal,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const columnas = 3;
        const espacio = 10.0;
        final lado = ((c.maxWidth - espacio * (columnas - 1)) / columnas).floorToDouble();
        return Wrap(
          spacing: espacio,
          runSpacing: espacio,
          children: [
            for (var i = 0; i < fotos.length; i++)
              SizedBox(
                width: lado,
                child: _FotoAdministrable(
                  fotos: fotos,
                  indice: i,
                  lado: lado,
                  fallida: fallidas.contains(fotos[i]),
                  ocupado: ocupado,
                  portada: conPortada && i == 0,
                  puedeHacerPrincipal: conPortada && i > 0 && onHacerPrincipal != null,
                  onQuitar: () => onQuitar(i),
                  onHacerPrincipal: onHacerPrincipal == null ? null : () => onHacerPrincipal!(i),
                ),
              ),
            if (!lleno)
              SizedBox(
                width: lado,
                height: lado,
                child: _CasillaAgregar(eligiendo: eligiendo, deshabilitada: ocupado || eligiendo, onTap: onAgregar),
              ),
          ],
        );
      },
    );
  }
}

class _FotoAdministrable extends StatelessWidget {
  final List<String> fotos;
  final int indice;
  final double lado;
  final bool fallida;
  final bool ocupado;
  final bool portada;
  final bool puedeHacerPrincipal;
  final VoidCallback onQuitar;
  final VoidCallback? onHacerPrincipal;

  const _FotoAdministrable({
    required this.fotos,
    required this.indice,
    required this.lado,
    required this.fallida,
    required this.ocupado,
    required this.portada,
    required this.puedeHacerPrincipal,
    required this.onQuitar,
    required this.onHacerPrincipal,
  });

  @override
  Widget build(BuildContext context) {
    final ruta = fotos[indice];
    final remota = _esRemota(ruta);
    final StatusPill estado;
    if (fallida) {
      estado = const StatusPill(label: 'No subida', tone: StatusTone.danger, compacto: true);
    } else if (!remota && ocupado) {
      estado = const StatusPill(label: 'Subiendo…', tone: StatusTone.info, compacto: true);
    } else if (!remota) {
      estado = const StatusPill(label: 'Por subir', tone: StatusTone.warning, compacto: true);
    } else {
      estado = const StatusPill(label: 'Subida', tone: StatusTone.success, compacto: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: lado,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(
                path: ruta,
                galeria: fotos,
                indiceEnGaleria: indice,
                width: lado,
                height: lado,
                borderRadius: BorderRadius.circular(AppRadius.card - 2),
              ),
              if (portada)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.coffeeMedium, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 12, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Portada', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.1)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: estado)),
              ),
              // Dentro de la foto y con área táctil de 40×40.
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  label: 'Quitar foto ${indice + 1}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: ocupado ? null : onQuitar,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 15, color: AppColors.coffeeDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (puedeHacerPrincipal)
          InkWell(
            onTap: ocupado ? null : onHacerPrincipal,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_border_rounded, size: 14, color: AppColors.coffeeMedium),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'Hacer principal',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.coffeeMedium, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CasillaAgregar extends StatelessWidget {
  final bool eligiendo;
  final bool deshabilitada;
  final VoidCallback onTap;
  const _CasillaAgregar({required this.eligiendo, required this.deshabilitada, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar fotos',
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card - 2),
          side: const BorderSide(color: AppColors.outlineStrong, width: 1.4),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card - 2)),
          onTap: deshabilitada ? null : onTap,
          child: Center(
            child: eligiendo
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.coffeeMedium))
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 26, color: AppColors.coffeeMedium),
                      SizedBox(height: 4),
                      Text('Agregar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.coffeeMedium)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
