import 'package:flutter/material.dart';
import '../../models/quote_request.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/status_pill.dart';

/// Tono semántico de cada estado de una cotización (misma paleta que
/// disponibilidad y solicitudes, ver [StatusTone]).
StatusTone toneEstadoCotizacion(EstadoCotizacion e) {
  switch (e) {
    case EstadoCotizacion.solicitudPendiente:
    case EstadoCotizacion.revisionSolicitada:
      return StatusTone.warning;
    case EstadoCotizacion.ofertaEnviada:
      return StatusTone.info;
    case EstadoCotizacion.ofertaAceptada:
      return StatusTone.success;
    case EstadoCotizacion.ofertaRechazada:
    case EstadoCotizacion.solicitudRechazada:
      return StatusTone.danger;
    case EstadoCotizacion.cancelada:
    case EstadoCotizacion.ofertaVencida:
      return StatusTone.neutral;
  }
}

Color colorEstadoCotizacion(EstadoCotizacion e) => toneEstadoCotizacion(e).foreground;

class QuoteStatusChip extends StatelessWidget {
  final EstadoCotizacion estado;
  final bool corto;
  const QuoteStatusChip({super.key, required this.estado, this.corto = true});

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: corto ? estado.corto : estado.label, tone: toneEstadoCotizacion(estado));
}

/// ¿Esta cotización espera una acción de quien la mira? (vendedor: solicitud o
/// ajuste por atender; comprador: oferta vigente por responder). Misma regla
/// que ya usaba la tarjeta; ahora también la usan las pestañas.
bool cotizacionRequiereAccion(QuoteRequest q, {required bool verComoVendedor}) => verComoVendedor
    ? QuoteStateMachine.requiereRespuestaDelVendedor(q.estado)
    : q.estadoEfectivo() == EstadoCotizacion.ofertaEnviada;

String cantidadTexto(double c, String unidad) {
  final t = c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toString();
  return '$t $unidad';
}

/// Tarjeta de una cotización en listas. [verComoVendedor] decide qué
/// contraparte se muestra. Usa [ActivityCard] para leerse igual que las
/// solicitudes enviadas.
class QuoteCard extends StatelessWidget {
  final QuoteRequest cotizacion;
  final bool verComoVendedor;
  final VoidCallback onTap;

  const QuoteCard({super.key, required this.cotizacion, required this.verComoVendedor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final q = cotizacion;
    final estado = q.estadoEfectivo();
    final otro = verComoVendedor ? q.compradorNombre : q.sellerNombre;
    final accion = cotizacionRequiereAccion(q, verComoVendedor: verComoVendedor);
    return ActivityCard(
      foto: q.loteFoto,
      titulo: q.loteNombre.isEmpty ? 'Café' : q.loteNombre,
      subtitulo: otro,
      detalles: [
        Text('Cantidad: ${cantidadTexto(q.cantidad, q.unidad)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        if (q.oferta != null)
          Text('Total ofertado: ${formatCOP(q.oferta!.totalCOP)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coffeeDark, fontSize: 14)),
      ],
      estado: QuoteStatusChip(estado: estado),
      fecha: formatFechaN(q.fecha),
      avisoAccion: accion ? 'Requiere tu respuesta' : null,
      onTap: onTap,
    );
  }
}
