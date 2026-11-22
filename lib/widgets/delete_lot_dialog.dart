import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lot_deletion.dart';
import '../repositories/repo_exception.dart';
import '../theme/app_theme.dart';

/// Cómo terminó una confirmación que SÍ se aceptó (cancelar devuelve `null`).
enum ResultadoEliminacion {
  /// La solicitud quedó guardada: el café sale del catálogo y el Worker termina de borrarlo.
  enviada,

  /// El servidor no respondió a tiempo. Firestore conserva la escritura y la envía al volver la
  /// conexión; el estado real lo muestra el catálogo («Eliminación pendiente»).
  sinRespuesta,
}

/// Pide confirmación para eliminar un café y, si la persona acepta, ejecuta [eliminar]
/// (en la app: `CoffeeLotRepository.eliminar(lote.id)`) DENTRO del diálogo, que mientras tanto
/// muestra el indicador de proceso y no se puede cerrar ni repetir.
///
/// Cancelar no ejecuta nada. Devuelve `null` si se canceló.
Future<ResultadoEliminacion?> mostrarConfirmacionEliminarCafe(
  BuildContext context, {
  required String nombreCafe,
  required Future<LotDeletionImpact> Function() contar,
  required Future<void> Function() eliminar,
}) {
  return showDialog<ResultadoEliminacion>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ConfirmarEliminarCafeDialog(nombreCafe: nombreCafe, contar: contar, eliminar: eliminar),
  );
}

class ConfirmarEliminarCafeDialog extends StatefulWidget {
  final String nombreCafe;
  final Future<LotDeletionImpact> Function() contar;
  final Future<void> Function() eliminar;

  /// Espera máxima de [eliminar] antes de cerrar con [ResultadoEliminacion.sinRespuesta].
  final Duration tiempoMaximo;

  const ConfirmarEliminarCafeDialog({
    super.key,
    required this.nombreCafe,
    required this.contar,
    required this.eliminar,
    this.tiempoMaximo = const Duration(seconds: 30),
  });

  @override
  State<ConfirmarEliminarCafeDialog> createState() => _ConfirmarEliminarCafeDialogState();
}

class _ConfirmarEliminarCafeDialogState extends State<ConfirmarEliminarCafeDialog> {
  bool _calculando = true;
  LotDeletionImpact? _impacto;
  RepoException? _errorConteo;
  bool _procesando = false;
  String? _errorEliminar;
  int _consulta = 0; // descarta respuestas de un intento anterior

  @override
  void initState() {
    super.initState();
    _cargarConteos();
  }

  Future<void> _cargarConteos() async {
    final mia = ++_consulta;
    try {
      final r = await widget.contar();
      if (!mounted || mia != _consulta) return;
      setState(() {
        _impacto = r;
        _errorConteo = null;
        _calculando = false;
      });
    } catch (e) {
      if (!mounted || mia != _consulta) return;
      setState(() {
        _impacto = null;
        _errorConteo = RepoException.desde(e);
        _calculando = false;
      });
    }
  }

  void _reintentarConteos() {
    setState(() {
      _calculando = true;
      _errorConteo = null;
    });
    _cargarConteos();
  }

  Future<void> _confirmar() async {
    // Sin conteos fiables no se confirma, y un segundo toque con la eliminación en marcha no
    // hace nada (la bandera se activa antes de cualquier `await`).
    if (_procesando || _impacto == null) return;
    setState(() {
      _procesando = true;
      _errorEliminar = null;
    });
    try {
      await widget.eliminar().timeout(widget.tiempoMaximo);
      if (!mounted) return;
      Navigator.of(context).pop(ResultadoEliminacion.enviada);
    } on TimeoutException {
      if (!mounted) return;
      Navigator.of(context).pop(ResultadoEliminacion.sinRespuesta);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _errorEliminar = RepoException.desde(e).mensaje;
      });
    }
  }

  static String _solicitudes(int n) => n == 1 ? '1 solicitud de interés' : '$n solicitudes de interés';
  static String _cotizaciones(int n) => n == 1 ? '1 cotización' : '$n cotizaciones';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_procesando,
      child: AlertDialog(
        title: const Text('Eliminar café'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vas a eliminar «${widget.nombreCafe}» de tu catálogo.', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              _bloqueConteos(textTheme),
              const SizedBox(height: 14),
              Text(
                'Las negociaciones comerciales se conservan: solicitudes, cotizaciones y chats siguen disponibles. '
                'Lo que dejará de mostrarse son las fotografías históricas de este café en esas negociaciones.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text('Esta acción no se puede deshacer.', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (_errorEliminar != null) ...[
                const SizedBox(height: 12),
                Text(_errorEliminar!, key: const ValueKey('error_eliminar'), style: textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _procesando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const ValueKey('confirmar_eliminar'),
            onPressed: (_procesando || _impacto == null) ? null : _confirmar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            child: _procesando
                ? const SizedBox(
                    key: ValueKey('eliminando_progreso'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Eliminar café'),
          ),
        ],
      ),
    );
  }

  Widget _bloqueConteos(TextTheme textTheme) {
    if (_calculando) {
      return Row(
        key: const ValueKey('conteos_calculando'),
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: 10),
          Expanded(child: Text('Calculando solicitudes y cotizaciones…', style: textTheme.bodyMedium)),
        ],
      );
    }
    final error = _errorConteo;
    if (error != null) {
      // Un fallo NUNCA se presenta como «0»: se dice que no se pudo calcular.
      return Column(
        key: const ValueKey('conteos_error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No pudimos calcular cuántas solicitudes y cotizaciones están relacionadas con este café. ${error.mensaje}',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: _procesando ? null : _reintentarConteos,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    final i = _impacto!;
    return Column(
      key: const ValueKey('conteos_listos'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Relacionadas con este café:', style: textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text('• ${_solicitudes(i.solicitudes)}', key: const ValueKey('conteo_solicitudes'), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('• ${_cotizaciones(i.cotizaciones)}', key: const ValueKey('conteo_cotizaciones'), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
