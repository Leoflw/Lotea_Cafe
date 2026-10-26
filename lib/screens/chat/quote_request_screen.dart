import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/interest_request.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/empty_state.dart';

/// Solicitud de cotización dentro de una conexión comercial (sección 13,
/// 1ª ronda; mejorada visualmente en la sección 20 de la 2ª ronda).
/// Muestra un resumen antes de enviar y no implementa pagos: deja la
/// arquitectura lista para cotización → pedido → pago.
class QuoteRequestScreen extends StatefulWidget {
  final InterestRequest conexion;
  const QuoteRequestScreen({super.key, required this.conexion});

  @override
  State<QuoteRequestScreen> createState() => _QuoteRequestScreenState();
}

class _QuoteRequestScreenState extends State<QuoteRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadCtrl = TextEditingController();
  final _comentarioCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  String _unidad = 'kg';

  @override
  void initState() {
    super.initState();
    for (final c in [_cantidadCtrl, _comentarioCtrl, _lugarCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _comentarioCtrl.dispose();
    _lugarCtrl.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!_formKey.currentState!.validate()) return;
    context.read<MockStore>().crearCotizacion(
          conexion: widget.conexion,
          cantidad: double.parse(_cantidadCtrl.text.trim()),
          unidad: _unidad,
          comentario: _comentarioCtrl.text.trim().isEmpty ? null : _comentarioCtrl.text.trim(),
          lugarEntrega: _lugarCtrl.text.trim().isEmpty ? null : _lugarCtrl.text.trim(),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud de cotización enviada'), backgroundColor: AppColors.leafGreen),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MockStore>();
    final lote = store.lotePorId(widget.conexion.coffeeLotId);
    final cotizacionesPrevias = store.cotizacionesDeConexion(widget.conexion.id);
    final cantidad = double.tryParse(_cantidadCtrl.text.trim());

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar cotización')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (lote != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.coffee, color: AppColors.coffeeMedium),
                title: Text(lote.nombre),
                subtitle: Text('${lote.proceso} · ${lote.varietyPrincipal} · ${formatCOPPorUnidad(lote.precioCOP, lote.unidad)}'),
              ),
            ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cantidad requerida', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _cantidadCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Ej: 50'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return (n == null || n <= 0) ? 'Cantidad inválida' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unidad,
                        items: const ['kg', 'lb', 'saco (70kg)'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (v) => setState(() => _unidad = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Lugar de entrega — opcional', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: _lugarCtrl, decoration: const InputDecoration(hintText: 'Ej: Bogotá, Colombia')),
                const SizedBox(height: 20),
                const Text('Comentario — opcional', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _comentarioCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Ej: Necesito el café para una cafetería.'),
                ),

                if (cantidad != null && cantidad > 0 && lote != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.coffeeLight.withOpacity(0.25), borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      'Estás solicitando una cotización para $cantidad $_unidad de "${lote.nombre}"'
                      '${_lugarCtrl.text.trim().isEmpty ? '' : ', con entrega en ${_lugarCtrl.text.trim()}'}.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                ElevatedButton(onPressed: _enviar, child: const Text('Enviar solicitud de cotización')),
              ],
            ),
          ),
          if (cotizacionesPrevias.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text('Cotizaciones anteriores', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...cotizacionesPrevias.map((c) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: AppColors.coffeeMedium),
                    title: Text('${c.cantidad.toStringAsFixed(0)} ${c.unidad}'),
                    subtitle: Text(c.comentario ?? 'Sin comentario'),
                    trailing: Text(c.estado.label, style: const TextStyle(fontSize: 12)),
                  ),
                )),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: EmptyState(icono: Icons.receipt_long_outlined, titulo: 'Sin cotizaciones previas para esta conexión'),
            ),
        ],
      ),
    );
  }
}
