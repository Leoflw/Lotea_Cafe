import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_profile.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../swipe/filters_sheet.dart' show variedadesDisponibles, procesosDisponibles;

/// Pantalla donde el vendedor crea/edita su perfil de café. Las fotos se
/// guardan como rutas locales del dispositivo (nada se sube a internet).
class SellerProfileEditScreen extends StatefulWidget {
  const SellerProfileEditScreen({super.key});

  @override
  State<SellerProfileEditScreen> createState() => _SellerProfileEditScreenState();
}

class _SellerProfileEditScreenState extends State<SellerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _fincaCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _altitudCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _inventarioCtrl = TextEditingController();

  final List<String> _variedadesSel = [];
  String _procesoSel = procesosDisponibles.first;
  final List<String> _certificacionesSel = [];
  final List<String> _rutasImagenes = [];

  CoffeeProfile? _perfilActual;
  bool _cargado = false;

  static const certificacionesDisponibles = ['Orgánico', 'Fair Trade', 'Origen certificado'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cargado) {
      _cargarPerfil();
      _cargado = true;
    }
  }

  @override
  void dispose() {
    _fincaCtrl.dispose();
    _descripcionCtrl.dispose();
    _altitudCtrl.dispose();
    _precioCtrl.dispose();
    _inventarioCtrl.dispose();
    super.dispose();
  }

  void _cargarPerfil() {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    final perfil = store.obtenerPerfilDeVendedor(uid);
    if (perfil != null) {
      _perfilActual = perfil;
      _fincaCtrl.text = perfil.finca;
      _descripcionCtrl.text = perfil.descripcion;
      _altitudCtrl.text = perfil.altitudMsnm?.toString() ?? '';
      _precioCtrl.text = perfil.precioPorKg.toString();
      _inventarioCtrl.text = perfil.inventarioKg?.toString() ?? '';
      _variedadesSel.addAll(perfil.variedades);
      _procesoSel = perfil.proceso.isNotEmpty ? perfil.proceso : procesosDisponibles.first;
      _certificacionesSel.addAll(perfil.certificaciones);
      _rutasImagenes.addAll(perfil.imagenes);
    }
    setState(() {});
  }

  Future<void> _elegirImagenes() async {
    final archivos = await _picker.pickMultiImage(imageQuality: 80);
    if (archivos.isNotEmpty) {
      setState(() {
        _rutasImagenes.addAll(archivos.map((x) => x.path));
      });
    }
  }

  void _guardar({required bool publicar}) {
    if (!_formKey.currentState!.validate()) return;
    if (_variedadesSel.isEmpty) {
      _mostrarError('Selecciona al menos una variedad.');
      return;
    }
    if (_rutasImagenes.isEmpty) {
      _mostrarError('Sube al menos una imagen del café.');
      return;
    }

    final store = context.read<MockStore>();
    final usuario = context.read<SessionProvider>().usuario!;

    final perfil = CoffeeProfile(
      id: _perfilActual?.id ?? 'perfil_${usuario.uid}',
      vendedorId: usuario.uid,
      nombreVendedor: usuario.nombre,
      finca: _fincaCtrl.text.trim(),
      variedades: List.from(_variedadesSel),
      altitudMsnm: double.tryParse(_altitudCtrl.text.trim()),
      proceso: _procesoSel,
      descripcion: _descripcionCtrl.text.trim(),
      imagenes: List.from(_rutasImagenes),
      precioPorKg: double.tryParse(_precioCtrl.text.trim()) ?? 0,
      inventarioKg: double.tryParse(_inventarioCtrl.text.trim()),
      certificaciones: List.from(_certificacionesSel),
      publicado: publicar,
    );

    store.guardarPerfil(perfil);
    setState(() => _perfilActual = perfil);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(publicar
            ? 'Perfil publicado. ¡Ya apareces en el feed de compradores!'
            : 'Borrador guardado.'),
        backgroundColor: AppColors.leafGreen,
      ),
    );
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil de café'),
        actions: [
          if (_perfilActual?.publicado == true)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Chip(
                  label: Text('Publicado', style: TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: AppColors.leafGreen,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _seccion('Fotos del café'),
            _galeriaImagenes(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirImagenes,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Agregar fotos'),
            ),
            const SizedBox(height: 20),
            _seccion('Finca / Origen'),
            TextFormField(
              controller: _fincaCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Finca La Esperanza, Huila'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 20),
            _seccion('Variedades de café'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: variedadesDisponibles.map((v) {
                final activo = _variedadesSel.contains(v);
                return FilterChip(
                  label: Text(v),
                  selected: activo,
                  selectedColor: AppColors.coffeeMedium,
                  labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                  onSelected: (sel) => setState(
                      () => sel ? _variedadesSel.add(v) : _variedadesSel.remove(v)),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _seccion('Proceso post-cosecha'),
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
            _seccion('Altitud (msnm) — opcional'),
            TextFormField(
              controller: _altitudCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Ej: 1750'),
            ),
            const SizedBox(height: 20),
            _seccion('Descripción / notas de sabor'),
            TextFormField(
              controller: _descripcionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Notas de cata, puntaje, historia de la finca…',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _seccion('Precio por kg (USD)'),
                      TextFormField(
                        controller: _precioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: 'Ej: 12.50'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return (n == null || n <= 0) ? 'Precio inválido' : null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _seccion('Inventario (kg) — opcional'),
                      TextFormField(
                        controller: _inventarioCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Ej: 500'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _seccion('Certificaciones'),
            Wrap(
              spacing: 8,
              children: certificacionesDisponibles.map((c) {
                final activo = _certificacionesSel.contains(c);
                return FilterChip(
                  label: Text(c),
                  selected: activo,
                  selectedColor: AppColors.coffeeMedium,
                  labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                  onSelected: (sel) => setState(
                      () => sel ? _certificacionesSel.add(c) : _certificacionesSel.remove(c)),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _guardar(publicar: true),
              child: const Text('Publicar perfil'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _guardar(publicar: false),
              child: const Text('Guardar como borrador'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _seccion(String titulo) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _galeriaImagenes() {
    if (_rutasImagenes.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.coffeeLight),
        ),
        child: const Center(
          child: Text('Sin fotos aún', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final ruta in _rutasImagenes)
            Container(
              margin: const EdgeInsets.only(right: 10),
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                image: DecorationImage(image: FileImage(File(ruta)), fit: BoxFit.cover),
              ),
            ),
        ],
      ),
    );
  }
}
