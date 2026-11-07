import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote_request.dart';
import '../../repositories/quote_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/dismiss_keyboard.dart';
import '../../widgets/form_widgets.dart';
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
    final textTheme = Theme.of(context).textTheme;
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    return DismissKeyboard(
      child: Scaffold(
        appBar: AppBar(title: Text(q.oferta == null ? 'Enviar oferta' : 'Enviar nueva oferta')),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // ---------- LO QUE PIDE EL COMPRADOR ----------
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: AppRadius.cardBorder),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${q.compradorNombre} solicita', style: textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(q.loteNombre, style: textTheme.headlineSmall?.copyWith(fontSize: 21, height: 1.15)),
                    const SizedBox(height: 6),
                    Text(cantidadTexto(q.cantidad, q.unidad), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                    if ((q.lugarEntrega ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 16, color: AppColors.inkSoft),
                          const SizedBox(width: 6),
                          Expanded(child: Text('Entrega en ${q.lugarEntrega}', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft))),
                        ],
                      ),
                    ],
                    if ((q.comentario ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('«${q.comentario}»', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft, fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
              if ((q.revisionComentario ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.edit_note, size: 20, color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Ajuste solicitado por el comprador: ${q.revisionComentario}', style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.coffeeDark)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 26),

              // ---------- PRECIO ----------
              FormSection(
                icono: Icons.sell_outlined,
                titulo: 'Precio',
                ayuda: 'Los importes son en pesos colombianos (COP).',
                children: [
                  FieldLabel('Precio por ${q.unidad}', obligatorio: true),
                  TextFormField(
                    controller: _precioCtrl,
                    enabled: !_enviando,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Ej: 32000', prefixText: r'$ ', suffixText: 'COP'),
                    validator: (v) => QuoteValidator.oferta(
                      precioUnitarioCOP: _entero(v ?? ''),
                      envioCOP: 0,
                      tiempoEntrega: 'x',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Costo de envío', opcional: true, ayuda: 'Escribe 0 si no aplica.'),
                  TextFormField(
                    controller: _envioCtrl,
                    enabled: !_enviando,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: r'$ ', suffixText: 'COP'),
                    validator: (v) {
                      final n = (v == null || v.trim().isEmpty) ? 0 : _entero(v);
                      if (n == null || n < 0) return 'Valor inválido';
                      return n > QuoteLimits.maxEnvio ? 'Valor demasiado alto' : null;
                    },
                  ),
                ],
              ),
              const FormSeparator(),

              // ---------- ENTREGA Y VIGENCIA ----------
              FormSection(
                icono: Icons.local_shipping_outlined,
                titulo: 'Entrega y vigencia',
                children: [
                  const FieldLabel('Tiempo estimado de entrega', obligatorio: true, ayuda: 'Por ejemplo: 5 días hábiles.'),
                  TextFormField(
                    controller: _entregaCtrl,
                    enabled: !_enviando,
                    maxLength: QuoteLimits.maxTiempoEntrega,
                    decoration: const InputDecoration(hintText: 'Ej: 5 días hábiles'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Indica el tiempo de entrega' : null,
                  ),
                  const FieldLabel('Vigencia de la oferta', opcional: true, ayuda: 'Hasta cuándo puede el comprador aceptarla.'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined, color: AppColors.coffeeMedium),
                    title: Text(_vigencia == null ? 'Sin fecha de vigencia' : 'Válida hasta ${formatFecha(_vigencia!)}'),
                    trailing: Wrap(children: [
                      if (_vigencia != null) IconButton(tooltip: 'Quitar vigencia', icon: const Icon(Icons.close), onPressed: () => setState(() => _vigencia = null)),
                      TextButton(onPressed: _enviando ? null : _elegirVigencia, child: const Text('Cambiar')),
                    ]),
                  ),
                ],
              ),
              const FormSeparator(),

              // ---------- CONDICIONES Y MENSAJE ----------
              FormSection(
                icono: Icons.description_outlined,
                titulo: 'Condiciones y mensaje',
                ayuda: 'Opcional.',
                children: [
                  const FieldLabel('Condiciones comerciales', ayuda: 'Formas de pago, entrega u otros acuerdos que propones.'),
                  TextFormField(
                    controller: _condicionesCtrl,
                    enabled: !_enviando,
                    maxLines: 3,
                    maxLength: QuoteLimits.maxCondiciones,
                  ),
                  const SizedBox(height: 6),
                  const FieldLabel('Mensaje para el comprador'),
                  TextFormField(
                    controller: _mensajeCtrl,
                    enabled: !_enviando,
                    maxLines: 2,
                    maxLength: QuoteLimits.maxMensaje,
                  ),
                ],
              ),
              const FormSeparator(),

              // ---------- RESUMEN ----------
              FormSection(
                icono: Icons.receipt_long_outlined,
                titulo: 'Resumen de la oferta',
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardBorder, border: Border.all(color: AppColors.outline)),
                    child: t == null
                        ? Text('Ingresa el precio para ver el total.', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft))
                        : Column(
                            children: [
                              _fila('Subtotal (${cantidadTexto(q.cantidad, q.unidad)})', formatCOP(t.subtotalCOP)),
                              _fila('Envío', formatCOP(t.envioCOP)),
                              const Divider(),
                              _fila('Total', formatCOP(t.totalCOP), fuerte: true),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Total siempre a la vista y el botón fijo; se oculta con el teclado abierto.
        bottomNavigationBar: tecladoAbierto
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.outline))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null) ...[
                          Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Total', style: textTheme.labelSmall),
                                  Text(t == null ? '—' : formatCOP(t.totalCOP), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _enviando ? null : _enviar,
                                child: _enviando
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                    : const Text('Enviar oferta'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _fila(String a, String b, {bool fuerte = false}) {
    final st = TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500, fontSize: fuerte ? 17 : 14, color: AppColors.coffeeDark);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text(a, style: st)), const SizedBox(width: 8), Text(b, style: st)]),
    );
  }
}
