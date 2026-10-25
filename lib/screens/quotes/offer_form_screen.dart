import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote_request.dart';
import '../../repositories/quote_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/dismiss_keyboard.dart';
import 'quote_widgets.dart';

/// El vendedor responde una solicitud con una oferta concreta. Los importes
/// se calculan con [QuoteCalculator]; las reglas de Firestore los verifican.
class OfferFormScreen extends StatefulWidget {
  final QuoteRequest cotizacion;
  const OfferFormScreen({super.key, required this.cotizacion});

  @override
  State<OfferFormScreen> createState() => _OfferFormScreenState();
}

class _OfferFormScreenState extends State<OfferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _precioCtrl = TextEditingController(text: widget.cotizacion.oferta?.precioUnitarioCOP.toString() ?? '');
  late final _envioCtrl = TextEditingController(text: (widget.cotizacion.oferta?.envioCOP ?? 0).toString());
  late final _entregaCtrl = TextEditingController(text: widget.cotizacion.oferta?.tiempoEntrega ?? '');
  late final _condicionesCtrl = TextEditingController(text: widget.cotizacion.oferta?.condiciones ?? '');
  late final _mensajeCtrl = TextEditingController();
  DateTime? _vigencia = DateTime.now().add(const Duration(days: 7));
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _precioCtrl.dispose();
    _envioCtrl.dispose();
    _entregaCtrl.dispose();
    _condicionesCtrl.dispose();
    _mensajeCtrl.dispose();
    super.dispose();
  }

  int? _entero(String t) => int.tryParse(t.trim().replaceAll('.', '').replaceAll(',', ''));

  QuoteTotals? get _totales {
    final p = _entero(_precioCtrl.text);
    final e = _entero(_envioCtrl.text) ?? 0;
    if (p == null || p <= 0 || e < 0) return null;
    return QuoteCalculator.calcular(cantidad: widget.cotizacion.cantidad, precioUnitarioCOP: p, envioCOP: e);
  }

  Future<void> _elegirVigencia() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: _vigencia ?? hoy.add(const Duration(days: 7)),
      firstDate: hoy.add(const Duration(days: 1)),
      lastDate: hoy.add(const Duration(days: 365)),
    );
    if (f != null) setState(() => _vigencia = DateTime(f.year, f.month, f.day, 23, 59));
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    final uid = context.read<SessionProvider>().usuario?.uid;
    if (uid == null) return;
    final navigator = Navigator.of(context);
    final repo = context.read<QuoteRepository>();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await repo.enviarOferta(
        quoteId: widget.cotizacion.id,
        vendedorUid: uid,
        precioUnitarioCOP: _entero(_precioCtrl.text)!,
        envioCOP: _entero(_envioCtrl.text) ?? 0,
        tiempoEntrega: _entregaCtrl.text,
        vigenciaHasta: _vigencia,
        condiciones: _condicionesCtrl.text,
        mensaje: _mensajeCtrl.text,
      );
      if (mounted) navigator.pop(true);
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.cotizacion;
    final t = _totales;
    return DismissKeyboard(
      child: Scaffold(
        appBar: AppBar(title: Text(q.oferta == null ? 'Enviar oferta' : 'Enviar nueva oferta')),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(q.loteNombre, style: Theme.of(context).textTheme.titleLarge),
              Text('${q.compradorNombre} solicita ${cantidadTexto(q.cantidad, q.unidad)}', style: TextStyle(color: Colors.grey.shade700)),
              if ((q.lugarEntrega ?? '').isNotEmpty) Text('Entrega en: ${q.lugarEntrega}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              if ((q.comentario ?? '').isNotEmpty) Text('Comentario: ${q.comentario}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              if ((q.revisionComentario ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.coffeeLight.withOpacity(0.35), borderRadius: BorderRadius.circular(12)),
                  child: Text('Ajuste solicitado por el comprador: ${q.revisionComentario}', style: const TextStyle(fontSize: 13)),
                ),
              ],
              const SizedBox(height: 18),
              TextFormField(
                controller: _precioCtrl,
                enabled: !_enviando,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Precio por ${q.unidad} (COP)', prefixText: '\$ '),
                validator: (v) => QuoteValidator.oferta(
                  precioUnitarioCOP: _entero(v ?? ''),
                  envioCOP: 0,
                  tiempoEntrega: 'x',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _envioCtrl,
                enabled: !_enviando,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Costo de envío (COP, 0 si no aplica)', prefixText: '\$ '),
                validator: (v) {
                  final n = (v == null || v.trim().isEmpty) ? 0 : _entero(v);
                  if (n == null || n < 0) return 'Valor inválido';
                  return n > QuoteLimits.maxEnvio ? 'Valor demasiado alto' : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _entregaCtrl,
                enabled: !_enviando,
                maxLength: QuoteLimits.maxTiempoEntrega,
                decoration: const InputDecoration(labelText: 'Tiempo estimado de entrega (ej. 5 días hábiles)', prefixIcon: Icon(Icons.local_shipping_outlined)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Indica el tiempo de entrega' : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(_vigencia == null ? 'Sin fecha de vigencia' : 'Oferta válida hasta ${formatFecha(_vigencia!)}'),
                trailing: Wrap(children: [
                  if (_vigencia != null) IconButton(tooltip: 'Quitar vigencia', icon: const Icon(Icons.close), onPressed: () => setState(() => _vigencia = null)),
                  TextButton(onPressed: _enviando ? null : _elegirVigencia, child: const Text('Cambiar')),
                ]),
              ),
              TextFormField(
                controller: _condicionesCtrl,
                enabled: !_enviando,
                maxLines: 3,
                maxLength: QuoteLimits.maxCondiciones,
                decoration: const InputDecoration(labelText: 'Condiciones comerciales (opcional)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _mensajeCtrl,
                enabled: !_enviando,
                maxLines: 2,
                maxLength: QuoteLimits.maxMensaje,
                decoration: const InputDecoration(labelText: 'Mensaje para el comprador (opcional)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
                child: t == null
                    ? const Text('Ingresa el precio para ver el total.')
                    : Column(
                        children: [
                          _fila('Subtotal (${cantidadTexto(q.cantidad, q.unidad)})', formatCOP(t.subtotalCOP)),
                          _fila('Envío', formatCOP(t.envioCOP)),
                          const Divider(),
                          _fila('Total', formatCOP(t.totalCOP), fuerte: true),
                        ],
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                child: _enviando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Enviar oferta'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(String a, String b, {bool fuerte = false}) {
    final st = TextStyle(fontWeight: fuerte ? FontWeight.bold : FontWeight.normal, fontSize: fuerte ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a, style: st), Text(b, style: st)]),
    );
  }
}
