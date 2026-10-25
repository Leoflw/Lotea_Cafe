import 'package:flutter/material.dart';
import '../../models/quote_request.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';

Color colorEstadoCotizacion(EstadoCotizacion e) {
  switch (e) {
    case EstadoCotizacion.solicitudPendiente:
    case EstadoCotizacion.revisionSolicitada:
      return AppColors.coffeeMedium;
    case EstadoCotizacion.ofertaEnviada:
      return const Color(0xFF2F6F9F);
    case EstadoCotizacion.ofertaAceptada:
      return AppColors.leafGreen;
    case EstadoCotizacion.ofertaRechazada:
    case EstadoCotizacion.solicitudRechazada:
      return AppColors.danger;
    case EstadoCotizacion.cancelada:
    case EstadoCotizacion.ofertaVencida:
      return Colors.grey.shade600;
  }
}

class QuoteStatusChip extends StatelessWidget {
  final EstadoCotizacion estado;
  final bool corto;
  const QuoteStatusChip({super.key, required this.estado, this.corto = true});

  @override
  Widget build(BuildContext context) {
    final c = colorEstadoCotizacion(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(corto ? estado.corto : estado.label,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

String cantidadTexto(double c, String unidad) {
  final t = c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toString();
  return '$t $unidad';
}

/// Tarjeta de una cotización en listas. [verComoVendedor] decide qué
/// contraparte se muestra.
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
    final accion = verComoVendedor
        ? QuoteStateMachine.requiereRespuestaDelVendedor(q.estado)
        : estado == EstadoCotizacion.ofertaEnviada;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppImage(path: q.loteFoto, width: 56, height: 56, borderRadius: BorderRadius.circular(12), ampliable: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.loteNombre.isEmpty ? 'Café' : q.loteNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(otro, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text('Cantidad: ${cantidadTexto(q.cantidad, q.unidad)}', style: const TextStyle(fontSize: 12.5)),
                    if (q.oferta != null)
                      Text('Total ofertado: ${formatCOP(q.oferta!.totalCOP)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.coffeeDark, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(formatFechaN(q.fecha), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QuoteStatusChip(estado: estado),
                  if (accion) ...[
                    const SizedBox(height: 6),
                    const Text('Requiere tu respuesta', style: TextStyle(color: AppColors.danger, fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
