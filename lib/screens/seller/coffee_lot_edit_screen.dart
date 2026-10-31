import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../repositories/coffee_lot_repository.dart';
import '../../repositories/image_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../services/photo_sync.dart';
import '../../state/activity_provider.dart';
import '../../widgets/remote_view.dart' show mostrarError;
import '../../theme/app_theme.dart';
import '../../utils/focus_utils.dart';
import '../../utils/image_validation.dart';
import '../../utils/lot_publish_policy.dart';
import '../../utils/photo_limits.dart';
import '../../widgets/dismiss_keyboard.dart';
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
  final Map<String, String> _idsPorUrl = {}; // URL ya subida → fileId de ImageKit
  final Set<String> _fallidas = {}; // fotos locales cuya subida falló (siguen en _fotos)
  late String? _loteId = widget.loteExistente?.id; // se fija al guardar un borrador nuevo
  bool _guardando = false;
  bool _eligiendo = false; // el selector de la galería está abierto (evita doble toque)
  String? _progreso;
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
      for (var i = 0; i < l.fotos.length && i < l.fotosStoragePaths.length; i++) {
        _idsPorUrl[l.fotos[i]] = l.fotosStoragePaths[i];
      }
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

  /// Fotos que ya tenía guardadas el documento que se está editando (0 en un
  /// café nuevo). Sirve para tolerar cafés antiguos con más fotos que el máximo.
  int get _fotosPrevias => widget.loteExistente?.fotos.length ?? 0;

  bool get _lleno => !PhotoLimits.puedeAgregar(_fotos.length, PhotoLimits.maxCafe);

  /// Reduce y comprime cada foto al elegirla (lado máximo 1600 px, calidad
  /// 80) y valida tipo y tamaño antes de aceptarla en el formulario. Solo se
  /// agregan las que caben en el máximo de [PhotoLimits.maxCafe].
  Future<void> _agregarFotos() async {
    if (_eligiendo || _guardando) return;
    if (_lleno) {
      _error(PhotoLimits.mensajeCafeLleno());
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
      final reparto = PhotoLimits.repartir(_fotos.length, PhotoLimits.maxCafe, archivos);
      final aceptadas = <String>[];
      var rechazadas = 0;
      String? motivo;
      for (final x in reparto.aceptadas) {
        try {
          ImageValidation.validar(await File(x.path).readAsBytes());
          aceptadas.add(x.path);
        } on RepoException catch (e) {
          rechazadas++;
          motivo = e.mensaje;
        } on FileSystemException {
          rechazadas++;
          motivo = 'No se pudo leer una de las imágenes.';
        }
      }
      if (!mounted) return;
      if (aceptadas.isNotEmpty) setState(() => _fotos.addAll(aceptadas));
      final avisos = <String>[
        if (rechazadas > 0) (rechazadas > 1 ? '$rechazadas imágenes no se agregaron. $motivo' : motivo!),
        if (reparto.descartadas > 0)
          PhotoLimits.mensajeSeleccionRecortada(
            agregadas: aceptadas.length,
            descartadas: reparto.descartadas,
            max: PhotoLimits.maxCafe,
            galeria: false,
          ),
      ];
      if (avisos.isNotEmpty) _error(avisos.join(' '));
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  void _quitarFoto(int i) {
    if (_guardando || i < 0 || i >= _fotos.length) return;
    setState(() {
      final ruta = _fotos.removeAt(i);
      _fallidas.remove(ruta);
      _idsPorUrl.remove(ruta); // los fileId se buscan por URL: quitar una no desordena las demás
    });
  }

  void _hacerPrincipal(int i) {
    if (_guardando || i <= 0 || i >= _fotos.length) return;
    setState(() {
      final foto = _fotos.removeAt(i);
      _fotos.insert(0, foto);
    });
  }

  Future<void> _guardar({required bool publicar}) async {
    if (_guardando || !_formKey.currentState!.validate()) return;
    if (_variedadesSel.isEmpty) {
      _error('Selecciona al menos una variedad.');
      return;
    }
    // Límite de fotos (también lo exigen el repositorio y firestore.rules).
    final exceso = PhotoLimits.validarCantidad(
      nuevo: _fotos.length,
      max: PhotoLimits.maxCafe,
      previo: _fotosPrevias,
      galeria: false,
    );
    if (exceso != null) {
      _error('$exceso Quita ${_fotos.length - PhotoLimits.maxCafe == 1 ? 'una foto' : '${_fotos.length - PhotoLimits.maxCafe} fotos'} para continuar.');
      return;
    }
    // Publicar exige foto; guardar un borrador no.
    final sinFotos = LotPublishPolicy.motivoBloqueo(publicar: publicar, fotosSubidas: _fotos.length, fotosFallidas: 0);
    if (sinFotos != null) {
      _error(sinFotos);
      return;
    }
    final perfil = context.read<ActivityProvider>().perfilVendedor;
    if (!perfil.listo || perfil.data == null) {
      _error('Primero completa el perfil de tu marca.');
      return;
    }
    final marca = perfil.data!;
    final repoLotes = context.read<CoffeeLotRepository>();
    final repoImagenes = context.read<ImageRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _guardando = true;
      _progreso = null;
    });
    try {
      // 1) Subir a ImageKit solo las fotos nuevas. Cada foto subida cambia su
      //    ruta local por la URL en el formulario, así un reintento no la
      //    repite. En un borrador, una foto fallida no impide guardar.
      final fotos = await PhotoSync.sincronizar(
        repo: repoImagenes,
        proposito: ImagePurpose.lot,
        fotos: _fotos,
        idsPorUrl: _idsPorUrl,
        continuarSiFalla: !publicar,
        alSubir: (local, url) {
          if (!mounted) return;
          setState(() {
            final i = _fotos.indexOf(local);
            if (i >= 0) _fotos[i] = url;
            _fallidas.remove(local);
          });
        },
        alProgresar: (h, t, p) {
          if (mounted && t > 0) setState(() => _progreso = 'Subiendo foto ${h + 1} de $t… ${(p * 100).round()}%');
        },
      );
      if (mounted) {
        setState(() {
          _fallidas
            ..clear()
            ..addAll(fotos.fallidas.map((f) => f.ruta));
        });
      }

      // Nunca se publica con fotos pendientes ni sin ninguna foto subida.
      final bloqueo = LotPublishPolicy.motivoBloqueo(
        publicar: publicar,
        fotosSubidas: fotos.urls.length,
        fotosFallidas: fotos.fallidas.length,
      );
      if (bloqueo != null) {
        if (mounted) _error(bloqueo);
        return;
      }
      if (mounted) setState(() => _progreso = 'Guardando café…');

      // 2) Guardar el lote con URLs remotas y datos del vendedor copiados. Solo
      //    las fotos subidas llegan a `fotos`: un lote con subida fallida no
      //    queda marcado como si tuviera foto.
      final lote = CoffeeLot(
        id: _loteId ?? '',
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
        fotos: fotos.urls,
        fotosStoragePaths: fotos.fileIds,
        sellerNombreMarca: marca.nombreMarca,
        departamento: marca.departamento,
        region: marca.region,
        municipio: marca.municipio,
        estado: publicar ? EstadoLote.publicado : EstadoLote.borrador,
      );
      _loteId = await repoLotes.guardarLote(lote, idExistente: _loteId);

      if (fotos.fallidas.isNotEmpty) {
        // Borrador guardado sin las fotos fallidas: la pantalla se queda abierta
        // (con esas fotos marcadas) para reintentar sin perder lo escrito.
        final n = fotos.fallidas.length;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(n == 1
                ? 'Borrador guardado, pero 1 foto no se pudo subir.'
                : 'Borrador guardado, pero $n fotos no se pudieron subir.'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Reintentar', textColor: Colors.white, onPressed: () => _guardar(publicar: false)),
          ));
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(publicar ? 'Café publicado en el catálogo.' : 'Borrador guardado.'),
          backgroundColor: AppColors.leafGreen,
        ),
      );
      liberarFoco();
      navigator.pop();
    } on RepoException catch (e) {
      // El formulario conserva lo escrito y lo ya subido; se puede reintentar.
      if (mounted) mostrarError(context, e, onReintentar: () => _guardar(publicar: publicar));
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _progreso = null;
        });
      }
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboard(
      child: Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar café' : 'Nuevo café')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _seccionMayor('Fotografías'),
            Row(
              children: [
                Expanded(child: _label('Fotos del lote')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    PhotoLimits.contadorCafe(_fotos.length),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: PhotoLimits.excedeMaximo(_fotos.length, PhotoLimits.maxCafe) ? AppColors.danger : AppColors.coffeeMedium,
                    ),
                  ),
                ),
              ],
            ),
            _galeriaFotos(),
            if (PhotoLimits.excedeMaximo(_fotos.length, PhotoLimits.maxCafe))
              _ayudaFotos(PhotoLimits.avisoCafeExcedido(_fotos.length), AppColors.danger)
            else if (_lleno)
              _ayudaFotos(PhotoLimits.mensajeCafeLleno(), AppColors.coffeeMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (_guardando || _eligiendo || _lleno) ? null : _agregarFotos,
              icon: _eligiendo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
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
            if (_progreso != null) ...[
              const LinearProgressIndicator(color: AppColors.coffeeMedium),
              const SizedBox(height: 6),
              Text(_progreso!, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
              const SizedBox(height: 10),
            ],
            ElevatedButton(
              onPressed: _guardando ? null : () => _guardar(publicar: true),
              child: _guardando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Publicar café'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _guardando ? null : () => _guardar(publicar: false),
              child: const Text('Guardar como borrador'),
            ),
            const SizedBox(height: 20),
          ],
        ),
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

  Widget _ayudaFotos(String texto, Color color) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(texto, style: TextStyle(color: color, fontSize: 12.5, height: 1.3)),
      );

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
    // La altura sigue al tamaño de texto del sistema para que las etiquetas
    // «Principal» / «Hacer principal» no se corten con el texto ampliado.
    final escala = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6).toDouble();
    return SizedBox(
      height: 90 + 40 * escala,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _fotos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final ruta = _fotos[i];
          return SizedBox(
            width: 90,
            child: Column(
              children: [
                Stack(
                  children: [
                    AppImage(path: ruta, galeria: _fotos, indiceEnGaleria: i, width: 90, height: 90, borderRadius: BorderRadius.circular(12)),
                    if (_fallidas.contains(ruta))
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
                          child: const Text('No subida', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    // Dentro de la foto (no fuera de sus bordes) y con área táctil de 40×40.
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Semantics(
                        button: true,
                        label: 'Quitar foto ${i + 1}',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _guardando ? null : () => _quitarFoto(i),
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
                const SizedBox(height: 2),
                if (i == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Principal', style: TextStyle(fontSize: 11, color: AppColors.leafGreen, fontWeight: FontWeight.bold)),
                  )
                else
                  InkWell(
                    onTap: _guardando ? null : () => _hacerPrincipal(i),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      child: Text(
                        'Hacer principal',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.coffeeMedium),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
