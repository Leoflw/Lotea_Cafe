import 'package:flutter/material.dart';
import '../models/interest_request.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';

/// Copia de visualización de un café tomada de una solicitud o conversación existente (el
/// comprador YA tiene ese documento). Sirve para mostrar datos básicos en solo lectura cuando
/// la ficha del café no se puede leer. No incluye fotografías a propósito: la pantalla no
/// descarga ni muestra imágenes del café no disponible.
class LoteRespaldo {
  final String nombre;
  final double? precioCOP;
  final String? unidad;
  final String vendedor;

  const LoteRespaldo({required this.nombre, this.precioCOP, this.unidad, this.vendedor = ''});

  factory LoteRespaldo.desdeConexion(InterestRequest c) =>
      LoteRespaldo(nombre: c.loteNombre, precioCOP: c.lotePrecioCOP, unidad: c.loteUnidad, vendedor: c.sellerNombreVisible);
}

/// Pantalla de indisponibilidad en lugar de un error técnico. Cubre un café suspendido (las
/// reglas no lo dejan leer a terceros), despublicado o eliminado: desde el cliente no se
/// distinguen, y no hace falta.
class CafeNoDisponibleView extends StatelessWidget {
  final LoteRespaldo? respaldo;
  const CafeNoDisponibleView({super.key, this.respaldo});

  @override
  Widget build(BuildContext context) {
    final r = respaldo;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: [
          const Icon(Icons.coffee_outlined, size: 56, color: AppColors.inkMuted),
          const SizedBox(height: 16),
          Text('Este café no está disponible', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Por ahora no se puede consultar la ficha completa. Tus mensajes, solicitudes y cotizaciones anteriores se conservan.',
            key: ValueKey('cafe_no_disponible_texto'),
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4, color: AppColors.inkSoft),
          ),
          if (r != null && r.nombre.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              key: const ValueKey('cafe_respaldo'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceWarm,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Datos guardados de tu conversación', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                  const SizedBox(height: 10),
                  _Fila('Café', r.nombre),
                  if (r.vendedor.isNotEmpty) _Fila('Vendedor', r.vendedor),
                  if (r.precioCOP != null) _Fila('Precio de referencia', formatCOPPorUnidad(r.precioCOP!, r.unidad ?? 'kg')),
                  const SizedBox(height: 6),
                  const Text(
                    'Información de solo lectura tomada cuando enviaste tu solicitud; puede haber cambiado.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Fila(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(etiqueta, style: const TextStyle(color: AppColors.inkSoft))),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.coffeeDark))),
        ],
      ),
    );
  }
}
