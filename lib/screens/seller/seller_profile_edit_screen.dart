import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/seller_profile.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_image.dart';

/// Edición del perfil de MARCA/finca del vendedor — separado de sus cafés
/// (sección 4 del plan de evolución). Este perfil es el que ve el
/// comprador en [SellerDetailScreen].
class SellerProfileEditScreen extends StatefulWidget {
  const SellerProfileEditScreen({super.key});

  @override
  State<SellerProfileEditScreen> createState() => _SellerProfileEditScreenState();
}

class _SellerProfileEditScreenState extends State<SellerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _marcaCtrl = TextEditingController();
  final _fincaCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _historiaCtrl = TextEditingController();
  final _aniosCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  String? _fotoPrincipal;
  final List<String> _galeria = [];
  String _departamentoSel = departamentosColombia.first;
  String? _tipoProduccion;

  SellerProfile? _actual;
  bool _cargado = false;

  static const tiposProduccion = ['Familiar', 'Cooperativa', 'Tecnificada'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cargado) {
      _cargar();
      _cargado = true;
    }
  }

  @override
  void dispose() {
    _marcaCtrl.dispose();
    _fincaCtrl.dispose();
    _descripcionCtrl.dispose();
    _historiaCtrl.dispose();
    _aniosCtrl.dispose();
    _municipioCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    final perfil = store.obtenerPerfilVendedor(uid);
    if (perfil != null) {
      _actual = perfil;
      _marcaCtrl.text = perfil.nombreMarca;
      _fincaCtrl.text = perfil.fincaPrincipal;
      _descripcionCtrl.text = perfil.descripcion;
      _historiaCtrl.text = perfil.historia;
      _aniosCtrl.text = perfil.aniosProduciendo?.toString() ?? '';
      _municipioCtrl.text = perfil.municipio;
      _telefonoCtrl.text = perfil.telefonoContacto ?? '';
      _fotoPrincipal = perfil.fotoPrincipal;
      _galeria.addAll(perfil.galeria);
      _departamentoSel = perfil.departamento;
      _tipoProduccion = perfil.tipoProduccion;
    }
    setState(() {});
  }

  Future<void> _elegirFotoPrincipal() async {
    final archivo = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (archivo != null) setState(() => _fotoPrincipal = archivo.path);
  }

  Future<void> _agregarGaleria() async {
    final archivos = await _picker.pickMultiImage(imageQuality: 80);
    if (archivos.isNotEmpty) {
      setState(() => _galeria.addAll(archivos.map((x) => x.path)));
    }
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final store = context.read<MockStore>();
    final usuario = context.read<SessionProvider>().usuario!;

    final perfil = SellerProfile(
      id: _actual?.id ?? 'perfil_${usuario.uid}',
      usuarioId: usuario.uid,
      nombreMarca: _marcaCtrl.text.trim(),
      fincaPrincipal: _fincaCtrl.text.trim(),
      fotoPrincipal: _fotoPrincipal,
      galeria: List.from(_galeria),
      descripcion: _descripcionCtrl.text.trim(),
      historia: _historiaCtrl.text.trim(),
      aniosProduciendo: int.tryParse(_aniosCtrl.text.trim()),
      tipoProduccion: _tipoProduccion,
      region: _departamentoSel,
      departamento: _departamentoSel,
      municipio: _municipioCtrl.text.trim(),
      telefonoContacto: _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
      verificado: _actual?.verificado ?? false,
      calificacionPromedio: _actual?.calificacionPromedio ?? 0,
      numOperaciones: _actual?.numOperaciones ?? 0,
      fechaRegistro: _actual?.fechaRegistro,
    );

    store.guardarPerfilVendedor(perfil);
    setState(() => _actual = perfil);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil de vendedor actualizado.'), backgroundColor: AppColors.leafGreen),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil de mi marca')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _elegirFotoPrincipal,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.coffeeLight,
                  backgroundImage: _fotoPrincipal != null ? FileImage(File(_fotoPrincipal!)) : null,
                  child: _fotoPrincipal == null
                      ? const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 28)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _label('Nombre de marca / productor'),
            TextFormField(
              controller: _marcaCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Finca La Esperanza'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            _label('Nombre de la finca'),
            TextFormField(
              controller: _fincaCtrl,
              decoration: const InputDecoration(hintText: 'Ej: Finca La Esperanza'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Departamento'),
                      DropdownButtonFormField<String>(
                        initialValue: _departamentoSel,
                        items: departamentosColombia
                            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (v) => setState(() => _departamentoSel = v!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Municipio'),
                      TextFormField(
                        controller: _municipioCtrl,
                        decoration: const InputDecoration(hintText: 'Ej: Pitalito'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('Teléfono de contacto — opcional'),
            TextFormField(
              controller: _telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Ej: 300 000 0000'),
            ),
            const SizedBox(height: 16),
            _label('Descripción breve'),
            TextFormField(
              controller: _descripcionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Ej: Productor de café especial desde 2015.'),
            ),
            const SizedBox(height: 20),
            _label('Sobre el productor (historia, filosofía)'),
            TextFormField(
              controller: _historiaCtrl,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Cuenta la historia de tu finca…'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Años produciendo — opcional'),
                      TextFormField(
                        controller: _aniosCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Ej: 12'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Tipo de producción'),
                      DropdownButtonFormField<String>(
                        initialValue: _tipoProduccion,
                        hint: const Text('Elegir'),
                        items: tiposProduccion
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) => setState(() => _tipoProduccion = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _label('Galería (finca, cafetales, proceso, empaque)'),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < _galeria.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppImage(
                            path: _galeria[i],
                            galeria: _galeria,
                            indiceEnGaleria: i,
                            width: 90,
                            height: 90,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => setState(() => _galeria.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: AppColors.danger,
                                child: Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  InkWell(
                    onTap: _agregarGaleria,
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.coffeeLight),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.coffeeMedium),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(onPressed: _guardar, child: const Text('Guardar perfil')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      );
}
