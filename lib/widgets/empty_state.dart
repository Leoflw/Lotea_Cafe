import 'package:flutter/material.dart';
import '../repositories/repo_exception.dart';
import '../theme/app_theme.dart';

/// Tono de un estado vacío o de error. Cambia el color del icono y del halo
/// para distinguir «aún no hay nada» (neutral) de «algo falló» (error), «sin
/// conexión» (info) o «hace falta algo de tu parte» (warning).
enum EmptyTone { neutral, error, info, warning }

/// Estado vacío reutilizable — evita pantallas en blanco (sección 25).
///
/// Composición: icono dentro de un halo circular, título, explicación en un
/// ancho cómodo de lectura y, si hay acción, un botón principal.
class EmptyState extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final String? textoAccion;
  final VoidCallback? onAccion;
  final EmptyTone tono;
  final IconData? iconoAccion;

  /// Acciones adicionales (por ejemplo varias opciones) bajo el texto.
  final List<Widget> acciones;

  const EmptyState({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.textoAccion,
    this.onAccion,
    this.tono = EmptyTone.neutral,
    this.iconoAccion,
    this.acciones = const [],
  });

  Color get _color {
    switch (tono) {
      case EmptyTone.neutral:
        return AppColors.coffeeMedium;
      case EmptyTone.error:
        return AppColors.danger;
      case EmptyTone.info:
        return AppColors.info;
      case EmptyTone.warning:
        return AppColors.warning;
    }
  }

  Color get _halo {
    switch (tono) {
      case EmptyTone.neutral:
        return AppColors.surfaceWarm;
      case EmptyTone.error:
        return AppColors.errorContainer;
      case EmptyTone.info:
        return AppColors.infoContainer;
      case EmptyTone.warning:
        return AppColors.warningContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tieneAccion = textoAccion != null && onAccion != null;
    final estiloBoton = ElevatedButton.styleFrom(minimumSize: const Size(200, 48));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(color: _halo, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: Icon(icono, size: 38, color: _color),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (subtitulo != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitulo!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                ),
              ],
              if (tieneAccion) ...[
                const SizedBox(height: 24),
                if (iconoAccion != null)
                  ElevatedButton.icon(
                    onPressed: onAccion,
                    icon: Icon(iconoAccion, size: 18),
                    label: Text(textoAccion!),
                    style: estiloBoton,
                  )
                else
                  ElevatedButton(onPressed: onAccion, style: estiloBoton, child: Text(textoAccion!)),
              ],
              if (acciones.isNotEmpty) ...[
                const SizedBox(height: 24),
                ...acciones,
              ],
            ],
          ),
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
      tono: EmptyTone.error,
      iconoAccion: Icons.refresh,
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
    late final EmptyTone tono;
    switch (error.tipo) {
      case RepoErrorKind.sinConexion:
        icono = Icons.wifi_off_outlined;
        titulo = 'Sin conexión';
        tono = EmptyTone.info;
      case RepoErrorKind.sinPermisos:
        icono = Icons.lock_outline;
        titulo = 'Sin permisos';
        tono = EmptyTone.warning;
      case RepoErrorKind.configuracionPendiente:
        icono = Icons.settings_suggest_outlined;
        titulo = 'Configuración pendiente';
        tono = EmptyTone.warning;
      case RepoErrorKind.sinSesion:
        icono = Icons.person_off_outlined;
        titulo = 'Sesión expirada';
        tono = EmptyTone.warning;
      default:
        icono = Icons.error_outline;
        titulo = 'No se pudo cargar';
        tono = EmptyTone.error;
    }
    return EmptyState(
      icono: icono,
      titulo: titulo,
      subtitulo: error.mensaje,
      textoAccion: onReintentar != null && error.tipo != RepoErrorKind.sinPermisos ? 'Reintentar' : null,
      onAccion: onReintentar,
      tono: tono,
      iconoAccion: Icons.refresh,
    );
  }
}
