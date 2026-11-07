import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';
import 'status_pill.dart';

/// Tarjeta común de actividad (cotizaciones y solicitudes enviadas), para que
/// ambas listas se lean igual: foto, título, contraparte, datos clave y, al
/// pie, el ESTADO junto a la fecha. Si algo espera una respuesta, aparece una
/// franja de aviso a todo el ancho en lugar de un texto suelto.
class ActivityCard extends StatelessWidget {
  final String? foto;
  final String titulo;
  final String subtitulo;

  /// Líneas de detalle entre la contraparte y el pie (cantidad, precio…).
  final List<Widget> detalles;
  final Widget estado;
  final String fecha;

  /// Acción discreta a la derecha del título (por ejemplo «Ver café»).
  final Widget? trailing;

  /// Texto de la franja de aviso; null = sin franja.
  final String? avisoAccion;

  /// Tono e icono de la franja (por defecto, «requiere tu respuesta»).
  final StatusTone avisoTono;
  final IconData avisoIcono;
  final VoidCallback? onTap;

  const ActivityCard({
    super.key,
    required this.foto,
    required this.titulo,
    required this.subtitulo,
    required this.estado,
    required this.fecha,
    this.detalles = const [],
    this.trailing,
    this.avisoAccion,
    this.avisoTono = StatusTone.warning,
    this.avisoIcono = Icons.notifications_active_outlined,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppImage(path: foto, width: 68, height: 68, borderRadius: BorderRadius.circular(14), ampliable: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (trailing != null) trailing!,
                          ],
                        ),
                        Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (detalles.isNotEmpty) const SizedBox(height: 6),
                        ...detalles,
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            estado,
                            Text(fecha, style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (avisoAccion != null)
              Container(
                color: avisoTono.background,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Icon(avisoIcono, size: 16, color: avisoTono.foreground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        avisoAccion!,
                        style: TextStyle(color: avisoTono.foreground, fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: avisoTono.foreground),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
