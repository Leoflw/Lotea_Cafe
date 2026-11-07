import 'package:flutter/material.dart';
import '../models/interest_request.dart';
import '../theme/app_theme.dart';

/// Tono semántico de un estado. Es el único vocabulario de color para
/// disponibilidad, cotizaciones y solicitudes:
/// * [success]: algo positivo y completado (disponible, aceptada).
/// * [warning]: espera una acción o respuesta (pendiente, revisión).
/// * [info]: avanzó y hay algo que revisar (oferta enviada).
/// * [danger]: terminó mal (rechazada).
/// * [neutral]: cerrado sin resultado (cancelada, vencida, agotado).
enum StatusTone { success, warning, info, danger, neutral }

extension StatusToneColors on StatusTone {
  Color get foreground {
    switch (this) {
      case StatusTone.success:
        return AppColors.success;
      case StatusTone.warning:
        return AppColors.warning;
      case StatusTone.info:
        return AppColors.info;
      case StatusTone.danger:
        return AppColors.danger;
      case StatusTone.neutral:
        return AppColors.inkSoft;
    }
  }

  Color get background {
    switch (this) {
      case StatusTone.success:
        return AppColors.successContainer;
      case StatusTone.warning:
        return AppColors.warningContainer;
      case StatusTone.info:
        return AppColors.infoContainer;
      case StatusTone.danger:
        return AppColors.errorContainer;
      case StatusTone.neutral:
        return AppColors.surfaceWarm;
    }
  }
}

/// Píldora de estado: punto de color + etiqueta. Es lo que distingue un
/// ESTADO (cambia con el tiempo) de un ATRIBUTO como una certificación o la
/// variedad, que usan formas rectangulares.
class StatusPill extends StatelessWidget {
  final String label;
  final StatusTone tone;

  /// Si se indica, reemplaza el punto por un icono.
  final IconData? icon;

  /// Versión pequeña para superponer sobre fotografías.
  final bool compacto;

  const StatusPill({super.key, required this.label, required this.tone, this.icon, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 7 : 10, vertical: compacto ? 3 : 4),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: compacto ? 11 : 13, color: fg)
          else
            Container(
              width: compacto ? 6 : 7,
              height: compacto ? 6 : 7,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          SizedBox(width: compacto ? 4 : 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: compacto ? 10.5 : 11.5, fontWeight: FontWeight.w800, height: 1.15),
            ),
          ),
        ],
      ),
    );
  }
}

StatusTone toneEstadoSolicitud(EstadoSolicitud e) {
  switch (e) {
    case EstadoSolicitud.pendiente:
      return StatusTone.warning;
    case EstadoSolicitud.aceptada:
      return StatusTone.success;
    case EstadoSolicitud.rechazada:
      return StatusTone.danger;
  }
}

/// Estado de una solicitud de interés (misma presentación que las
/// cotizaciones y la disponibilidad).
class RequestStatusChip extends StatelessWidget {
  final EstadoSolicitud estado;
  const RequestStatusChip({super.key, required this.estado});

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: estado.label, tone: toneEstadoSolicitud(estado));
}
