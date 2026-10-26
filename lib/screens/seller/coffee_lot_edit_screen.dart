import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_lot.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';

/// Crear/editar UN café/lote. Un vendedor puede tener varios (sección 4):
/// esta pantalla siempre trabaja sobre un lote a la vez, nunca sobre "el"
/// perfil de café del vendedor como en el MVP original.
class CoffeeLotEditScreen extends StatefulWidget {
  final String sellerId;
  final CoffeeLot? loteExistente;

  const CoffeeLotEditScreen({super.key, required this.sellerId, this.loteExistente});

  @override
  State<CoffeeLotEditScreen> createState() => _CoffeeLotEditScreenState();
}

class _CoffeeLotEditScreenState extends State<CoffeeLotEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _altitudCtrl = TextEditingController();
  final _puntajeCtrl = TextEditingController();
  final _cosechaCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController();
  final _pedidoMinCtrl = TextEditingController();

  final List<String> _variedadesSel = [];
  String _procesoSel = procesosDisponibles.first;
  String? _tipoCafeSel;
  String _unidadSel = 'kg';
  final List<String> _certificacionesSel = [];
  final List<String> _metodosEnvioSel = [];
  final List<String> _fotos = [];
  final List<String> _notasCataSel = [];
  String? _acidezSel;
  String? _cuerpoSel;
  String? _dulzorSel;
  bool _disponible = true;

  static const notasCataDisponibles = [
    'Cítrico', 'Floral', 'Frutos rojos', 'Panela', 'Chocolate', 'Miel', 'Fermentado dulce', 'Nuez',
  ];
  static const metodosEnvioDisponibles = ['Envío nacional', 'Envío internacional', 'Recogida en finca'];

  bool get _editando => widget.loteExistente != null;

  @override
  void initState() {
    super.initState();
    final l = widget.loteExistente;
    if (l != null) {
      _nombreCtrl.text = l.nombre;
      _precioCtrl.text = l.precioCOP.toStringAsFixed(0);
      _descripcionCtrl.text = l.descripcion;
      _altitudCtrl.text = l.altitudMsnm?.toStringAsFixed(0) ?? '';
      _puntajeCtrl.text = l.puntajeTaza?.toString() ?? '';
      _cosechaCtrl.text = l.cosecha ?? '';
      _cantidadCtrl.text = l.cantidadDisponibleKg?.toStringAsFixed(0) ?? '';
      _pedidoMinCtrl.text = l.pedidoMinimoKg?.toStringAsFixed(0) ?? '';
      _variedadesSel.addAll(l.variedades);
      _procesoSel = l.proceso;
      _tipoCafeSel = l.tipoCafe;
      _unidadSel = l.unidad;
      _certificacionesSel.addAll(l.certificaciones);
      _metodosEnvioSel.addAll(l.metodosEnvio);
      _fotos.addAll(l.fotos);
      _notasCataSel.addAll(l.perfilSensorial.notas);
      _acidezSel = l.perfilSensorial.acidez;
      _cuerpoSel = l.perfilSensorial.cuerpo;
      _dulzorSel = l.perfilSensorial.dulzor;
      _disponible = l.disponible;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _descripcionCtrl.dispose();
    _altitudCtrl.dispose();
    _puntajeCtrl.dispose();
    _cosechaCtrl.dispose();
    _cantidadCtrl.dispose();
    _pedidoMinCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregarFotos() async {
    final archivos = await _picker.pickMultiImage(imageQuality: 80);
    if (archivos.isNotEmpty) setState(() => _fotos.addAll(archivos.map((x) => x.path)));
  }

  void _guardar({required bool publicar}) {
    if (!_formKey.currentState!.validate()) return;
    if (_variedadesSel.isEmpty) {
      _error('Selecciona al menos una variedad.');
      return;
    }

    final store = context.read<MockStore>();
    final lote = CoffeeLot(
      id: widget.loteExistente?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      sellerId: widget.sellerId,
      nombre: _nombreCtrl.text.trim(),
      variedades: List.from(_variedadesSel),
      proceso: _procesoSel,
      tipoCafe: _tipoCafeSel,
      altitudMsnm: double.tryParse(_altitudCtrl.text.trim()),
      puntajeTaza: double.tryParse(_puntajeCtrl.text.trim()),
      cosecha: _cosechaCtrl.text.trim().isEmpty ? null : _cosechaCtrl.text.trim(),
      perfilSensorial: TasteProfile(
        notas: List.from(_notasCataSel),
        acidez: _acidezSel,
        cuerpo: _cuerpoSel,
        dulzor: _dulzorSel,
      ),
      descripcion: _descripcionCtrl.text.trim(),
      precioCOP: double.tryParse(_precioCtrl.text.trim()) ?? 0,
      unidad: _unidadSel,
      cantidadDisponibleKg: double.tryParse(_cantidadCtrl.text.trim()),
      pedidoMinimoKg: double.tryParse(_pedidoMinCtrl.text.trim()),
      disponible: _disponible,
      metodosEnvio: List.from(_metodosEnvioSel),
      certificaciones: List.from(_certificacionesSel),
      fotos: List.from(_fotos),
      estado: publicar ? EstadoLote.publicado : EstadoLote.borrador,
      fechaPublicacion: widget.loteExistente?.fechaPublicacion,
    );

    store.guardarLote(lote);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(publicar ? 'Café publicado en el catálogo.' : 'Borrador guardado.'),
        backgroundColor: AppColors.leafGreen,
      ),
    );
    Navigator.of(context).pop();
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar café' : 'Nuevo café')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _seccionMayor('Fotografías'),
            _label('Fotos del lote'),
            _galeriaFotos(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _agregarFotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Agregar fotos'),
            ),
            const SizedBox(height: 24),
            _seccionMayor('Identidad'),
            _label('Nombre del café'),
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Caturra Lavado'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 24),
            _seccionMayor('Proceso y calidad'),
            _label('Variedad'),
            _chips(variedadesDisponibles, _variedadesSel),
            const SizedBox(height: 20),
            _label('Proceso'),
            Wrap(
              spacing: 8,
              children: procesosDisponibles.map((p) {
                final activo = _procesoSel == p;
                return ChoiceChip(
                  label: Text(p),
                  selected: activo,
                  selectedColor: AppColors.leafGreen,
                  labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                  onSelected: (_) => setState(() => _procesoSel = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _label('Tipo de café — opcional'),
            Wrap(
              spacing: 8,
              children: tiposCafeDisponibles.map((t) {
                final activo = _tipoCafeSel == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: activo,
                  selectedColor: AppColors.coffeeMedium,
                  labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                  onSelected: (sel) => setState(() => _tipoCafeSel = sel ? t : null),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            _seccionMayor('Venta'),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Precio (COP)'),
                      TextFormField(
                        controller: _precioCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Ej: 32000'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return (n == null || n <= 0) ? 'Precio inválido' : null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Unidad'),
                      DropdownButtonFormField<String>(
                        initialValue: _unidadSel,
                        items: unidadesDisponibles
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setState(() => _unidadSel = v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Disponible (kg) — opcional'),
                      TextFormField(
                        controller: _cantidadCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          return (n == null || n <= 0) ? 'Debe ser mayor a 0' : null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Pedido mínimo (kg) — opcional'),
                      TextFormField(
                        controller: _pedidoMinCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          return (n == null || n < 0) ? 'Valor inválido' : null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponible actualmente'),
              value: _disponible,
              activeThumbColor: AppColors.coffeeMedium,
              onChanged: (v) => setState(() => _disponible = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Altitud (msnm) — opcional'),
                      TextFormField(
                        controller: _altitudCtrl,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          return (n == null || n < 0) ? 'Altitud inválida' : null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Puntaje de taza — opcional'),
                      TextFormField(
                        controller: _puntajeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          return (n == null || n < 50 || n > 100) ? 'Entre 50 y 100' : null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('Cosecha — opcional'),
            TextFormField(controller: _cosechaCtrl, decoration: const InputDecoration(hintText: 'Ej: 2025-2')),
            const SizedBox(height: 20),
            _label('Descripción'),
            TextFormField(controller: _descripcionCtrl, maxLines: 3),
            const SizedBox(height: 24),
            _label('Perfil de taza — opcional'),
            _chips(notasCataDisponibles, _notasCataSel),
            const SizedBox(height: 12),
            _nivelSelector('Acidez', _acidezSel, (v) => setState(() => _acidezSel = v)),
            _nivelSelector('Cuerpo', _cuerpoSel, (v) => setState(() => _cuerpoSel = v)),
            _nivelSelector('Dulzor', _dulzorSel, (v) => setState(() => _dulzorSel = v)),
            const SizedBox(height: 24),
            _seccionMayor('Certificaciones y envío'),
            _label('Métodos de envío'),
            _chips(metodosEnvioDisponibles, _metodosEnvioSel),
            const SizedBox(height: 20),
            _label('Certificaciones'),
            _chips(certificacionesDisponibles, _certificacionesSel),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: () => _guardar(publicar: true), child: const Text('Publicar café')),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _guardar(publicar: false),
              child: const Text('Guardar como borrador'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _seccionMayor(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.coffeeDark)),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: AppColors.coffeeLight, thickness: 1)),
          ],
        ),
      );

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _chips(List<String> opciones, List<String> seleccionados) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opciones.map((op) {
        final activo = seleccionados.contains(op);
        return FilterChip(
          label: Text(op),
          selected: activo,
          selectedColor: AppColors.coffeeMedium,
          labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
          onSelected: (sel) => setState(() => sel ? seleccionados.add(op) : seleccionados.remove(op)),
        );
      }).toList(),
    );
  }

  Widget _nivelSelector(String etiqueta, String? valor, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: nivelesSensoriales.map((n) {
                final activo = valor == n;
                return ChoiceChip(
                  label: Text(n, style: const TextStyle(fontSize: 12)),
                  selected: activo,
                  visualDensity: VisualDensity.compact,
                  selectedColor: AppColors.leafGreen,
                  labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                  onSelected: (sel) => onChanged(sel ? n : null),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _galeriaFotos() {
    if (_fotos.isEmpty) {
      return Container(
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.coffeeLight),
        ),
        child: const Center(child: Text('Sin fotos aún', style: TextStyle(color: Colors.grey))),
      );
    }
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _fotos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final ruta = _fotos[i];
          return Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppImage(path: ruta, galeria: _fotos, indiceEnGaleria: i, width: 90, height: 90, borderRadius: BorderRadius.circular(12)),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: () => setState(() => _fotos.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: AppColors.danger,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (i == 0)
                const Text('Principal', style: TextStyle(fontSize: 9.5, color: AppColors.leafGreen, fontWeight: FontWeight.bold))
              else
                GestureDetector(
                  onTap: () => setState(() {
                    final foto = _fotos.removeAt(i);
                    _fotos.insert(0, foto);
                  }),
                  child: const Text('Hacer principal', style: TextStyle(fontSize: 9.5, color: AppColors.coffeeMedium)),
                ),
            ],
          );
        },
      ),
    );
  }
}
