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
import '../../widgets/form_widgets.dart';
import '../../widgets/photo_grid.dart';
import '../../widgets/status_pill.dart';
import '../../utils/format_utils.dart';

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
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) {
      // Antes se salía sin avisar; con el formulario en secciones el campo
      // con error puede quedar fuera de pantalla.
      _error('Revisa los campos marcados en rojo.');
      return;
    }
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

  static const _explicacionProceso = {
    'Lavado': 'Se despulpa y se lava con agua antes de secar: sabor limpio y brillante.',
    'Natural': 'Se seca con la cereza completa: más dulce y afrutado.',
    'Honey': 'Se seca con parte del mucílago del grano: dulzor intermedio.',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final perfilMarca = context.read<ActivityProvider>().perfilVendedor;
    final marca = perfilMarca.listo ? perfilMarca.data : null;
    // Con el teclado abierto la barra de acciones se oculta: no le quita
    // altura al formulario mientras se escribe.
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    final excede = PhotoLimits.excedeMaximo(_fotos.length, PhotoLimits.maxCafe);

    return DismissKeyboard(
      child: Scaffold(
        appBar: AppBar(title: Text(_editando ? 'Editar café' : 'Nuevo café')),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(
                'Los campos con * son obligatorios. Un borrador solo necesita nombre, precio y una variedad; para publicar también hace falta al menos una foto.',
                style: textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 24),

              // ---------- 1. INFORMACIÓN BÁSICA ----------
              FormSection(
                icono: Icons.local_cafe_outlined,
                titulo: 'Información básica',
                children: [
                  const FieldLabel('Nombre del café', obligatorio: true, ayuda: 'El nombre con el que los compradores verán este lote.'),
                  TextFormField(
                    controller: _nombreCtrl,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Ej: Caturra Lavado'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Descripción', opcional: true, ayuda: 'Cuenta qué hace especial este lote: su sabor, su historia, cómo se cultivó.'),
                  TextFormField(
                    controller: _descripcionCtrl,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  if (marca != null) ...[
                    const SizedBox(height: 18),
                    _OrigenDelLote(ubicacion: marca.ubicacionCorta, finca: marca.fincaPrincipal),
                  ],
                ],
              ),
              const FormSeparator(),

              // ---------- 2. FOTOGRAFÍAS ----------
              FormSection(
                icono: Icons.photo_library_outlined,
                titulo: 'Fotografías',
                ayuda: 'La primera foto es la portada de tu publicación; puedes cambiarla con «Hacer principal». Máximo ${PhotoLimits.maxCafe} fotos.',
                trailing: Text(
                  PhotoLimits.contadorCafe(_fotos.length),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: excede ? AppColors.danger : AppColors.coffeeMedium),
                ),
                children: [
                  PhotoGrid(
                    fotos: _fotos,
                    fallidas: _fallidas,
                    lleno: _lleno,
                    ocupado: _guardando,
                    eligiendo: _eligiendo,
                    conPortada: true,
                    onAgregar: _agregarFotos,
                    onQuitar: _quitarFoto,
                    onHacerPrincipal: _hacerPrincipal,
                  ),
                  const SizedBox(height: 10),
                  if (excede)
                    Text(PhotoLimits.avisoCafeExcedido(_fotos.length), style: const TextStyle(color: AppColors.danger, fontSize: 12.5, height: 1.3))
                  else if (_lleno)
                    Text(PhotoLimits.mensajeCafeLleno(), style: const TextStyle(color: AppColors.coffeeMedium, fontSize: 12.5, height: 1.3))
                  else
                    Text(
                      '«Por subir» significa que la foto aún está solo en tu teléfono: se sube al guardar. Para publicar, todas deben subirse bien.',
                      style: textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                ],
              ),
              const FormSeparator(),

              // ---------- 3. CARACTERÍSTICAS Y PROCESO ----------
              FormSection(
                icono: Icons.eco_outlined,
                titulo: 'Características y proceso',
                children: [
                  const FieldLabel('Variedad', obligatorio: true, ayuda: 'La variedad (o variedades) de café de este lote. Elige todas las que apliquen.'),
                  _chips(variedadesDisponibles, _variedadesSel),
                  const SizedBox(height: 20),
                  const FieldLabel('Proceso', ayuda: 'Cómo se trató el grano después de cosechar.'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: procesosDisponibles
                        .map((p) => OptionChip(texto: p, activo: _procesoSel == p, unica: true, onSelected: (_) => setState(() => _procesoSel = p)))
                        .toList(),
                  ),
                  if (_explicacionProceso[_procesoSel] != null) ...[
                    const SizedBox(height: 8),
                    Text(_explicacionProceso[_procesoSel]!, style: textTheme.bodySmall?.copyWith(height: 1.4)),
                  ],
                  const SizedBox(height: 20),
                  const FieldLabel('Tipo de café', opcional: true, ayuda: 'La clasificación general de tu lote.'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tiposCafeDisponibles
                        .map((t) => OptionChip(texto: t, activo: _tipoCafeSel == t, unica: true, onSelected: (sel) => setState(() => _tipoCafeSel = sel ? t : null)))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('Altitud', opcional: true, ayuda: 'Metros sobre el nivel del mar donde creció.'),
                  TextFormField(
                    controller: _altitudCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Ej: 1700', suffixText: 'msnm'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      return (n == null || n < 0) ? 'Altitud inválida' : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Puntaje de taza', opcional: true, ayuda: 'Nota de catación, de 50 a 100.'),
                  TextFormField(
                    controller: _puntajeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Ej: 86.5', suffixText: 'pts'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      return (n == null || n < 50 || n > 100) ? 'Entre 50 y 100' : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Cosecha', opcional: true, ayuda: 'El año y ciclo en que se cosechó.'),
                  TextFormField(
                    controller: _cosechaCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Ej: 2025-2'),
                  ),
                ],
              ),
              const FormSeparator(),

              // ---------- 4. PERFIL SENSORIAL ----------
              FormSection(
                icono: Icons.local_florist_outlined,
                titulo: 'Perfil de taza',
                ayuda: 'Opcional. Ayuda a los compradores a imaginar cómo sabe tu café.',
                children: [
                  const FieldLabel('Notas de cata', ayuda: 'Los sabores y aromas que se perciben en la taza.'),
                  _chips(notasCataDisponibles, _notasCataSel),
                  const SizedBox(height: 20),
                  _nivelSelector('Acidez', 'La sensación viva y fresca, como la de una fruta cítrica.', _acidezSel, (v) => setState(() => _acidezSel = v)),
                  _nivelSelector('Cuerpo', 'El peso o la textura del café en la boca.', _cuerpoSel, (v) => setState(() => _cuerpoSel = v)),
                  _nivelSelector('Dulzor', 'Qué tan dulce se siente el café.', _dulzorSel, (v) => setState(() => _dulzorSel = v)),
                ],
              ),
              const FormSeparator(),

              // ---------- 5. PRECIO Y DISPONIBILIDAD ----------
              FormSection(
                icono: Icons.sell_outlined,
                titulo: 'Precio y disponibilidad',
                ayuda: 'Todos los importes son en pesos colombianos (COP).',
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Precio', obligatorio: true, ayuda: 'Lo que cobras por cada unidad.'),
                            TextFormField(
                              controller: _precioCtrl,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'Ej: 32000', prefixText: r'$ ', suffixText: 'COP'),
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
                            const FieldLabel('Unidad de venta', ayuda: 'La presentación en que vendes.'),
                            DropdownButtonFormField<String>(
                              initialValue: _unidadSel,
                              isExpanded: true,
                              items: unidadesDisponibles.map((u) => DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setState(() => _unidadSel = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Vista previa de cómo verán el precio los compradores.
                  ListenableBuilder(
                    listenable: _precioCtrl,
                    builder: (context, _) {
                      final n = double.tryParse(_precioCtrl.text.trim());
                      if (n == null || n <= 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Los compradores verán: ${formatCOPPorUnidad(n, _unidadSel)}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.coffeeMedium)),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Cantidad disponible', opcional: true, ayuda: 'Cuántos kg tienes listos para vender.'),
                  TextFormField(
                    controller: _cantidadCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Ej: 120', suffixText: 'kg'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      return (n == null || n <= 0) ? 'Debe ser mayor a 0' : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Pedido mínimo', opcional: true, ayuda: 'La menor cantidad que aceptas vender.'),
                  TextFormField(
                    controller: _pedidoMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Ej: 10', suffixText: 'kg'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = double.tryParse(v.trim());
                      return (n == null || n < 0) ? 'Valor inválido' : null;
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponible actualmente', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Si lo desactivas, tu café se muestra como agotado.'),
                    value: _disponible,
                    activeThumbColor: AppColors.coffeeMedium,
                    onChanged: (v) => setState(() => _disponible = v),
                  ),
                ],
              ),
              const FormSeparator(),

              // ---------- 6. CERTIFICACIONES Y ENVÍO ----------
              FormSection(
                icono: Icons.verified_outlined,
                titulo: 'Certificaciones y envío',
                ayuda: 'Opcional.',
                children: [
                  const FieldLabel('Métodos de envío', ayuda: 'Cómo puedes entregar el café.'),
                  _chips(metodosEnvioDisponibles, _metodosEnvioSel),
                  const SizedBox(height: 20),
                  const FieldLabel('Certificaciones', ayuda: 'Sellos que respaldan tu café. Marca solo los que realmente tengas.'),
                  _chips(certificacionesDisponibles, _certificacionesSel),
                ],
              ),
              const FormSeparator(),

              // ---------- 7. REVISIÓN Y PUBLICACIÓN ----------
              FormSection(
                icono: Icons.fact_check_outlined,
                titulo: 'Revisión y publicación',
                trailing: _editando
                    ? StatusPill(
                        label: widget.loteExistente!.publicado ? 'Publicado' : 'Borrador',
                        tone: widget.loteExistente!.publicado ? StatusTone.success : StatusTone.warning,
                      )
                    : null,
                children: [
                  ListenableBuilder(
                    listenable: Listenable.merge([_nombreCtrl, _precioCtrl]),
                    builder: (context, _) {
                      final precio = double.tryParse(_precioCtrl.text.trim()) ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RequisitoPublicacion(texto: 'Nombre del café', cumplido: _nombreCtrl.text.trim().isNotEmpty),
                          _RequisitoPublicacion(texto: 'Precio mayor a 0', cumplido: precio > 0),
                          _RequisitoPublicacion(texto: 'Al menos una variedad', cumplido: _variedadesSel.isNotEmpty),
                          _RequisitoPublicacion(texto: 'Al menos una foto (solo para publicar)', cumplido: _fotos.isNotEmpty),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Al publicar, primero se suben las fotos nuevas. Si alguna falla, el café no se publica hasta que todas se suban bien; un borrador sí se guarda.',
                    style: textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: tecladoAbierto ? null : _barraAcciones(),
      ),
    );
  }

  /// Acciones siempre a mano: borrador y publicar quedan fijas bajo el
  /// formulario (se ocultan solo con el teclado abierto).
  Widget _barraAcciones() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_progreso != null) ...[
                const LinearProgressIndicator(color: AppColors.coffeeMedium, backgroundColor: AppColors.surfaceWarm),
                const SizedBox(height: 4),
                Text(_progreso!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _guardando ? null : () => _guardar(publicar: false),
                      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Guardar borrador')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _guardando ? null : () => _guardar(publicar: true),
                      child: _guardando
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const FittedBox(fit: BoxFit.scaleDown, child: Text('Publicar café')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips(List<String> opciones, List<String> seleccionados) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opciones
          .map((op) => OptionChip(
                texto: op,
                activo: seleccionados.contains(op),
                onSelected: (sel) => setState(() => sel ? seleccionados.add(op) : seleccionados.remove(op)),
              ))
          .toList(),
    );
  }

  /// Selector de nivel (Bajo / Medio / Alto) con una explicación sencilla.
  Widget _nivelSelector(String etiqueta, String explicacion, String? valor, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(etiqueta, ayuda: explicacion),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: nivelesSensoriales
                .map((n) => OptionChip(texto: n, activo: valor == n, unica: true, onSelected: (sel) => onChanged(sel ? n : null)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// Muestra de dónde sale el origen del lote: no se escribe aquí, se toma del
/// perfil de la marca.
class _OrigenDelLote extends StatelessWidget {
  final String ubicacion;
  final String finca;
  const _OrigenDelLote({required this.ubicacion, required this.finca});

  @override
  Widget build(BuildContext context) {
    final detalle = [if (finca.isNotEmpty) finca, ubicacion].where((e) => e.trim().isNotEmpty).join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.place_outlined, size: 20, color: AppColors.coffeeMedium),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Origen del lote', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                if (detalle.isNotEmpty) Text(detalle, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.coffeeDark)),
                const SizedBox(height: 2),
                Text('Se toma del perfil de tu marca; para cambiarlo, edita el perfil.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequisitoPublicacion extends StatelessWidget {
  final String texto;
  final bool cumplido;
  const _RequisitoPublicacion({required this.texto, required this.cumplido});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(cumplido ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: cumplido ? AppColors.success : AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 14, fontWeight: cumplido ? FontWeight.w600 : FontWeight.w500, color: cumplido ? AppColors.coffeeDark : AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
