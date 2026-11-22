import 'dart:async';
import 'package:flutter/material.dart';
import '../repositories/repo_exception.dart';
import '../state/remote.dart';
import '../theme/app_theme.dart';
import 'empty_state.dart';

class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.coffeeMedium)),
      );
}

/// Pinta un [Remote]: cargando, error (con reintento) o datos. Los estados
/// vacíos los decide cada pantalla dentro de [builder].
class RemoteView<T> extends StatelessWidget {
  final Remote<T> remote;
  final Widget Function(T data) builder;
  final VoidCallback? onReintentar;

  const RemoteView({super.key, required this.remote, required this.builder, this.onReintentar});

  @override
  Widget build(BuildContext context) {
    if (remote.cargando) return const _Cargando();
    if (remote.fallo) return RepoErrorView(error: remote.error!, onReintentar: onReintentar);
    return builder(remote.data);
  }
}

/// Escucha un documento o consulta de Firestore con estados de carga y
/// error. [crear] se vuelve a llamar al reintentar. El stream se cancela al
/// salir de la pantalla.
class StreamView<T> extends StatefulWidget {
  final Stream<T> Function() crear;
  final Widget Function(BuildContext context, T data) builder;

  /// Pantalla propia para un fallo (p. ej. «café no disponible» en lugar de un error técnico).
  /// Sin él se muestra el error genérico con «Reintentar», como siempre.
  final Widget Function(BuildContext context, RepoException error, VoidCallback reintentar)? errorBuilder;

  const StreamView({super.key, required this.crear, required this.builder, this.errorBuilder});

  @override
  State<StreamView<T>> createState() => _StreamViewState<T>();
}

class _StreamViewState<T> extends State<StreamView<T>> {
  late Stream<T> _stream = widget.crear();

  void _reintentar() => setState(() => _stream = widget.crear());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = RepoException.desde(snap.error!);
          final propio = widget.errorBuilder;
          if (propio != null) return propio(context, e, _reintentar);
          return RepoErrorView(error: e, onReintentar: _reintentar);
        }
        // Antes de que llegue el primer evento sí se está cargando.
        if (snap.connectionState == ConnectionState.waiting) return const _Cargando();
        // Si T admite null (p. ej. `CoffeeLot?`), un evento `null` es un DATO («el documento no existe»), no
        // «cargando»: `snap.hasData` es falso en ese caso y dejaba el indicador girando para siempre. Si T no
        // admite null y no hay dato (stream cerrado sin emitir), se mantiene el indicador como antes.
        if (!snap.hasData && null is! T) return const _Cargando();
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

/// Muestra un SnackBar de error con el mensaje de la excepción.
/// Si se pasa [onReintentar] y el error es recuperable (red, servicio
/// ocupado), el SnackBar incluye el botón «Reintentar».
void mostrarError(BuildContext context, Object error, {VoidCallback? onReintentar}) {
  final e = RepoException.desde(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(e.mensaje),
      backgroundColor: AppColors.danger,
      duration: onReintentar != null ? const Duration(seconds: 8) : const Duration(seconds: 4),
      action: (onReintentar != null && e.esRecuperable)
          ? SnackBarAction(label: 'Reintentar', textColor: Colors.white, onPressed: onReintentar)
          : null,
    ));
}
