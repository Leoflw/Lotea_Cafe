import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/coffee_lot.dart';
import '../../models/interest_request.dart';
import '../../models/quote_request.dart';
import '../../repositories/coffee_lot_repository.dart';
import '../../repositories/quote_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';
import '../../widgets/dismiss_keyboard.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/form_widgets.dart';
import '../../widgets/price_text.dart';
import 'quote_detail_screen.dart';

/// El comprador solicita una cotización dentro de una conexión aceptada.
/// No hay pagos ni pedidos: es una solicitud de precio y condiciones.
class QuoteRequestScreen extends StatefulWidget {
  final InterestRequest conexion;
  const QuoteRequestScreen({super.key, required this.conexion});

  @override
  State<QuoteRequestScreen> createState() => _QuoteRequestScreenState();
}

class _QuoteRequestScreenState extends State<QuoteRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  final _comentarioCtrl = TextEditingController();
  // Un solo id por pantalla: reintentar el envío no duplica la cotización.
  final String _quoteId = const Uuid().v4();

  CoffeeLot? _lote;
  RepoException? _errorCarga;
  bool _cargandoLote = true;
  bool _enviando = false;
  String _unidad = 'kg';
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarLote();
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _lugarCtrl.dispose();
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarLote() async {
    setState(() {
      _cargandoLote = true;
      _errorCarga = null;
    });
    try {
      final l = await context.read<CoffeeLotRepository>().obtener(widget.conexion.coffeeLotId);
      if (!mounted) return;
      setState(() {
        _lote = l;
        if (l != null && QuoteLimits.unidadesPermitidas.contains(l.unidad)) _unidad = l.unidad;
      });
    } on RepoException catch (e) {
      if (mounted) setState(() => _errorCarga = e);
    } finally {
      if (mounted) setState(() => _cargandoLote = false);
    }
  }

  Future<void> _enviar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    final lote = _lote;
    final uid = context.read<SessionProvider>().usuario?.uid;
    if (lote == null || uid == null) return;
    final navigator = Navigator.of(context);
    final repo = context.read<QuoteRepository>();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await repo.crearSolicitud(
        quoteId: _quoteId,
        conexion: widget.conexion,
        lote: lote,
        compradorUid: uid,
        cantidad: double.parse(_cantidadCtrl.text.replaceAll(',', '.')),
        unidad: _unidad,
        lugarEntrega: _lugarCtrl.text,
        comentario: _comentarioCtrl.text,
      );
      if (!mounted) return;
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: _quoteId)));
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lote = _lote;
    return DismissKeyboard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Solicitar cotización')),
        body: _cargandoLote
            ? const Center(child: CircularProgressIndicator(color: AppColors.coffeeMedium))
            : _errorCarga != null
                ? RepoErrorView(error: _errorCarga!, onReintentar: _cargarLote)
                : lote == null
                    ? const EmptyState(icono: Icons.coffee_outlined, titulo: 'Este café ya no está disponible')
                    : Form(
                        key: _formKey,
                        child: ListView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          children: [
                            _ResumenCafe(lote: lote),
                            const SizedBox(height: 26),
                            FormSection(
                              icono: Icons.scale_outlined,
                              titulo: 'Qué necesitas',
                              ayuda: lote.pedidoMinimoKg != null
                                  ? 'El pedido mínimo de este café es de ${lote.pedidoMinimoKg!.toStringAsFixed(0)} kg.'
                                  : 'Indica cuánto café quieres comprar.',
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const FieldLabel('Cantidad', obligatorio: true),
                                          TextFormField(
                                            controller: _cantidadCtrl,
                                            enabled: !_enviando,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(hintText: 'Ej: 50'),
                                            validator: (v) {
                                              final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                                              return QuoteValidator.solicitud(cantidad: n, unidad: _unidad);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const FieldLabel('Unidad'),
                                          DropdownButtonFormField<String>(
                                            initialValue: _unidad,
                                            isExpanded: true,
                                            items: QuoteLimits.unidadesPermitidas
                                                .map((u) => DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis)))
                                                .toList(),
                                            onChanged: _enviando ? null : (v) => setState(() => _unidad = v ?? _unidad),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const FormSeparator(),
                            FormSection(
                              icono: Icons.local_shipping_outlined,
                              titulo: 'Entrega',
                              children: [
                                const FieldLabel('Lugar de entrega', opcional: true, ayuda: 'La ciudad o dirección donde quieres recibir el café.'),
                                TextFormField(
                                  controller: _lugarCtrl,
                                  enabled: !_enviando,
                                  maxLength: QuoteLimits.maxLugar,
                                  decoration: const InputDecoration(hintText: 'Ej: Bogotá', prefixIcon: Icon(Icons.place_outlined)),
                                ),
                              ],
                            ),
                            const FormSeparator(),
                            FormSection(
                              icono: Icons.notes_outlined,
                              titulo: 'Observaciones',
                              children: [
                                const FieldLabel('Comentario', opcional: true, ayuda: 'Cualquier detalle que el vendedor deba tener en cuenta.'),
                                TextFormField(
                                  controller: _comentarioCtrl,
                                  enabled: !_enviando,
                                  maxLines: 3,
                                  maxLength: QuoteLimits.maxComentario,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppColors.infoContainer, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 19, color: AppColors.info),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Esto es una solicitud de precio y condiciones. Lotea Café aún no procesa pagos, pedidos ni envíos: '
                                      'los acuerdan directamente comprador y vendedor.',
                                      style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.coffeeDark),
                                    ),
                                  ),
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
                                  : const FittedBox(fit: BoxFit.scaleDown, child: Text('Enviar solicitud de cotización')),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}

/// Resumen del café sobre el que se pide cotización: foto, nombre, vendedor y
/// precio de lista (referencia; el precio real lo propone el vendedor).
class _ResumenCafe extends StatelessWidget {
  final CoffeeLot lote;
  const _ResumenCafe({required this.lote});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: AppRadius.cardBorder),
      child: Row(
        children: [
          AppImage(path: lote.fotoPrincipal, galeria: lote.fotosRemotas, width: 76, height: 76, borderRadius: BorderRadius.circular(AppRadius.card - 2), ampliable: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lote.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.headlineSmall?.copyWith(fontSize: 20, height: 1.15)),
                if (lote.sellerNombreMarca.isNotEmpty) Text(lote.sellerNombreMarca, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                const SizedBox(height: 6),
                Text('Precio de lista', style: textTheme.labelSmall),
                PriceText(valor: lote.precioCOP, unidad: lote.unidad, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
