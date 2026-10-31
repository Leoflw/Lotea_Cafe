import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/seller_profile.dart';
import '../../repositories/image_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../repositories/seller_repository.dart';
import '../../services/photo_sync.dart';
import '../../state/activity_provider.dart';
import '../../state/session_provider.dart';
import '../../widgets/remote_view.dart' show mostrarError;
import '../../theme/app_theme.dart';
import '../../utils/focus_utils.dart';
import '../../utils/image_validation.dart';
import '../../utils/photo_limits.dart';
import '../../widgets/avatar_circular.dart';
import '../../widgets/dismiss_keyboard.dart';
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
  final Map<String, String> _idsPorUrl = {}; // URL ya subida → fileId de ImageKit
  bool _guardando = false;
  bool _eligiendo = false; // el selector de la galería está abierto (evita doble toque)
  String? _progreso;
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
    final remoto = context.read<ActivityProvider>().perfilVendedor;
    final perfil = remoto.listo ? remoto.data : null;
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
      if (perfil.fotoPrincipal != null && perfil.fotoPrincipalStoragePath != null) {
        _idsPorUrl[perfil.fotoPrincipal!] = perfil.fotoPrincipalStoragePath!;
      }
      for (var i = 0; i < perfil.galeria.length && i < perfil.galeriaStoragePaths.length; i++) {
        _idsPorUrl[perfil.galeria[i]] = perfil.galeriaStoragePaths[i];
      }
      _departamentoSel = perfil.departamento;
      _tipoProduccion = perfil.tipoProduccion;
    }
    setState(() {});
  }

  /// Valida tipo y tamaño de la foto elegida. Devuelve `false` y avisa si no
  /// es válida.
  Future<bool> _validarArchivo(String ruta) async {
    try {
      ImageValidation.validar(await File(ruta).readAsBytes());
      return true;
    } on RepoException catch (e) {
      if (mounted) mostrarError(context, e);
    } on FileSystemException {
      if (mounted) {
        mostrarError(context, const RepoException(RepoErrorKind.otro, 'No se pudo leer la imagen seleccionada.'));
      }
    }
    return false;
  }

  Future<void> _elegirFotoPrincipal() async {
    if (_eligiendo || _guardando) return;
    setState(() => _eligiendo = true);
    try {
      final archivo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: ImageValidation.pickerQuality,
        maxWidth: ImageValidation.pickerMaxSide,
        maxHeight: ImageValidation.pickerMaxSide,
      );
      if (archivo == null || !await _validarArchivo(archivo.path)) return;
      if (mounted) setState(() => _fotoPrincipal = archivo.path);
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  /// Fotos de galería que ya tenía guardadas el perfil (0 si es nuevo). Sirve
  /// para tolerar perfiles antiguos con más fotos que el máximo.
  int get _galeriaPrevia => _actual?.galeria.length ?? 0;

  bool get _galeriaLlena => !PhotoLimits.puedeAgregar(_galeria.length, PhotoLimits.maxGaleriaMarca);

  /// Agrega fotos a la galería (la foto principal es aparte y no cuenta).
  /// Solo entran las que caben en [PhotoLimits.maxGaleriaMarca].
  Future<void> _agregarGaleria() async {
    if (_eligiendo || _guardando) return;
    if (_galeriaLlena) {
      mostrarError(context, RepoException(RepoErrorKind.validacion, PhotoLimits.mensajeGaleriaLlena()));
      return;
    }
    setState(() => _eligiendo = true);
    try {
      final archivos = await _picker.pickMultiImage(
        imageQuality: ImageValidation.pickerQuality,
        maxWidth: ImageValidation.pickerMaxSide,
        maxHeight: ImageValidation.pickerMaxSide,
      );
      if (archivos.isEmpty) return;
      final reparto = PhotoLimits.repartir(_galeria.length, PhotoLimits.maxGaleriaMarca, archivos);
      final aceptadas = <String>[];
      for (final x in reparto.aceptadas) {
        if (await _validarArchivo(x.path)) aceptadas.add(x.path);
      }
      if (!mounted) return;
      if (aceptadas.isNotEmpty) setState(() => _galeria.addAll(aceptadas));
      if (reparto.descartadas > 0) {
        mostrarError(
          context,
          RepoException(
            RepoErrorKind.validacion,
            PhotoLimits.mensajeSeleccionRecortada(
              agregadas: aceptadas.length,
              descartadas: reparto.descartadas,
              max: PhotoLimits.maxGaleriaMarca,
              galeria: true,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  void _quitarDeGaleria(int i) {
    if (_guardando || i < 0 || i >= _galeria.length) return;
    setState(() {
      final ruta = _galeria.removeAt(i);
      _idsPorUrl.remove(ruta);
    });
  }

  Future<void> _guardar() async {
    if (_guardando || !_formKey.currentState!.validate()) return;
    final exceso = PhotoLimits.validarCantidad(
      nuevo: _galeria.length,
      max: PhotoLimits.maxGaleriaMarca,
      previo: _galeriaPrevia,
      galeria: true,
    );
    if (exceso != null) {
      mostrarError(context, RepoException(RepoErrorKind.validacion, '$exceso Quita ${_galeria.length - PhotoLimits.maxGaleriaMarca == 1 ? 'una foto' : '${_galeria.length - PhotoLimits.maxGaleriaMarca} fotos'} para continuar.'));
      return;
    }
    final usuario = context.read<SessionProvider>().usuario!;
    final imagenes = context.read<ImageRepository>();
    final vendedores = context.read<SellerRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _guardando = true;
      _progreso = null;
    });
    try {
      // 1) Subir a ImageKit solo las fotos nuevas. Si una falla, no se guarda
      //    nada; las ya subidas cambian su ruta local por la URL, así el
      //    reintento no las repite.
      String? urlPrincipal;
      String? idPrincipal;
      if (_fotoPrincipal != null) {
        final r = await PhotoSync.sincronizar(
          repo: imagenes,
          proposito: ImagePurpose.profile,
          fotos: [_fotoPrincipal!],
          idsPorUrl: _idsPorUrl,
          alSubir: (local, url) {
            if (mounted && _fotoPrincipal == local) setState(() => _fotoPrincipal = url);
          },
          alProgresar: (h, t, p) {
            if (mounted && t > 0) setState(() => _progreso = 'Subiendo foto principal… ${(p * 100).round()}%');
          },
        );
        urlPrincipal = r.urls.first;
        idPrincipal = r.fileIds.first;
      }
      final g = await PhotoSync.sincronizar(
        repo: imagenes,
        proposito: ImagePurpose.profile,
        fotos: _galeria,
        idsPorUrl: _idsPorUrl,
        alSubir: (local, url) {
          if (!mounted) return;
          setState(() {
            final i = _galeria.indexOf(local);
            if (i >= 0) _galeria[i] = url;
          });
        },
        alProgresar: (h, t, p) {
          if (mounted && t > 0) setState(() => _progreso = 'Subiendo foto ${h + 1} de $t… ${(p * 100).round()}%');
        },
      );
      if (mounted) setState(() => _progreso = 'Guardando perfil…');

      // 2) Guardar el perfil con las URLs remotas (nunca rutas locales).
      final perfil = SellerProfile(
        id: usuario.uid,
        usuarioId: usuario.uid,
        nombreMarca: _marcaCtrl.text.trim(),
        fincaPrincipal: _fincaCtrl.text.trim(),
        fotoPrincipal: urlPrincipal,
        fotoPrincipalStoragePath: idPrincipal,
        galeria: g.urls,
        galeriaStoragePaths: g.fileIds,
        descripcion: _descripcionCtrl.text.trim(),
        historia: _historiaCtrl.text.trim(),
        aniosProduciendo: int.tryParse(_aniosCtrl.text.trim()),
        tipoProduccion: _tipoProduccion,
        region: _departamentoSel,
        departamento: _departamentoSel,
        municipio: _municipioCtrl.text.trim(),
        telefonoContacto: _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
      );
      await vendedores.guardarPerfil(perfil);

      messenger.showSnackBar(
        const SnackBar(content: Text('Perfil de vendedor actualizado.'), backgroundColor: AppColors.leafGreen),
      );
      liberarFoco();
      navigator.pop();
    } on RepoException catch (e) {
      // Los datos escritos en el formulario se conservan para reintentar.
      if (mounted) mostrarError(context, e, onReintentar: _guardar);
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _progreso = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(
      child: Scaffold(
      appBar: AppBar(title: const Text('Perfil de mi marca')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Semantics(
                button: true,
                label: _fotoPrincipal == null ? 'Agregar foto principal de la marca' : 'Cambiar foto principal de la marca',
                child: GestureDetector(
                  onTap: (_guardando || _eligiendo) ? null : _elegirFotoPrincipal,
                  child: _fotoPrincipal == null
                      ? const CircleAvatar(
                          radius: 48,
                          backgroundColor: AppColors.coffeeLight,
                          child: Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 28),
                        )
                      : AvatarCircular(fotoUrl: _fotoPrincipal, nombre: _marcaCtrl.text, radius: 48, fontSize: 34),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _fotoPrincipal == null ? 'Toca el círculo para agregar la foto principal' : 'Toca el círculo para cambiar la foto principal',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
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
            Row(
              children: [
                Expanded(child: _label('Galería (finca, cafetales, proceso, empaque)')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: Text(
                    PhotoLimits.contadorGaleria(_galeria.length),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: PhotoLimits.excedeMaximo(_galeria.length, PhotoLimits.maxGaleriaMarca) ? AppColors.danger : AppColors.coffeeMedium,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < _galeria.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          AppImage(
                            path: _galeria[i],
                            galeria: _galeria,
                            indiceEnGaleria: i,
                            width: 90,
                            height: 90,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          // Dentro de la foto y con área táctil de 40×40.
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Semantics(
                              button: true,
                              label: 'Quitar foto ${i + 1} de la galería',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _guardando ? null : () => _quitarDeGaleria(i),
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(4),
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: AppColors.danger,
                                        child: Icon(Icons.close, size: 15, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_galeriaLlena)
                    Semantics(
                      button: true,
                      label: 'Agregar fotos a la galería',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: (_guardando || _eligiendo) ? null : _agregarGaleria,
                        child: Container(
                          width: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.coffeeLight),
                          ),
                          child: _eligiendo
                              ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                              : const Icon(Icons.add_photo_alternate_outlined, color: AppColors.coffeeMedium),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (PhotoLimits.excedeMaximo(_galeria.length, PhotoLimits.maxGaleriaMarca))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(PhotoLimits.avisoGaleriaExcedida(_galeria.length), style: const TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.3)),
              )
            else if (_galeriaLlena)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(PhotoLimits.mensajeGaleriaLlena(), style: const TextStyle(color: AppColors.coffeeMedium, fontSize: 12.5, height: 1.3)),
              ),
            const SizedBox(height: 28),
            if (_progreso != null) ...[
              LinearProgressIndicator(color: AppColors.coffeeMedium),
              const SizedBox(height: 6),
              Text(_progreso!, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Guardar perfil'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      ),
    );
  }

  Widget _label(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      );
}
