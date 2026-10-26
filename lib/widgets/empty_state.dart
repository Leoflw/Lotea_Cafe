import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estado vacío reutilizable — evita pantallas en blanco (sección 25).
class EmptyState extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final String? textoAccion;
  final VoidCallback? onAccion;

  const EmptyState({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.textoAccion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: AppColors.coffeeLight),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitulo!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
            if (textoAccion != null && onAccion != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAccion, child: Text(textoAccion!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mensaje de error amigable reutilizable.
class ErrorState extends StatelessWidget {
  final String mensaje;
  final VoidCallback? onReintentar;

  const ErrorState({super.key, required this.mensaje, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icono: Icons.error_outline,
      titulo: 'Algo no salió bien',
      subtitulo: mensaje,
      textoAccion: onReintentar != null ? 'Reintentar' : null,
      onAccion: onReintentar,
    );
  }
}
