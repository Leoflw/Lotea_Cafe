import 'package:flutter/material.dart';
import '../repositories/repo_exception.dart';
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

/// Error de datos remotos: distingue sin conexión, sin permisos y
/// configuración pendiente; nunca se muestra como "lista vacía".
class RepoErrorView extends StatelessWidget {
  final RepoException error;
  final VoidCallback? onReintentar;

  const RepoErrorView({super.key, required this.error, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    late final IconData icono;
    late final String titulo;
    switch (error.tipo) {
      case RepoErrorKind.sinConexion:
        icono = Icons.wifi_off_outlined;
        titulo = 'Sin conexión';
      case RepoErrorKind.sinPermisos:
        icono = Icons.lock_outline;
        titulo = 'Sin permisos';
      case RepoErrorKind.configuracionPendiente:
        icono = Icons.settings_suggest_outlined;
        titulo = 'Configuración pendiente';
      case RepoErrorKind.sinSesion:
        icono = Icons.person_off_outlined;
        titulo = 'Sesión expirada';
      default:
        icono = Icons.error_outline;
        titulo = 'No se pudo cargar';
    }
    return EmptyState(
      icono: icono,
      titulo: titulo,
      subtitulo: error.mensaje,
      textoAccion: onReintentar != null && error.tipo != RepoErrorKind.sinPermisos ? 'Reintentar' : null,
      onAccion: onReintentar,
    );
  }
}
