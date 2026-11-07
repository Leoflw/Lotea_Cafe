import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/coffee_lot.dart';
import '../../models/discover_filters.dart';
import '../../repositories/coffee_lot_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../services/home_tab_notifier.dart';
import '../../state/activity_provider.dart';
import '../../state/session_provider.dart';
import '../../utils/catalog_logic.dart';
import '../../widgets/empty_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/focus_utils.dart';
import 'filters_sheet.dart';
import 'list_mode_view.dart';
import 'search_screen.dart';
import 'swipe_mode_view.dart';

enum ModoDescubrimiento { tarjetas, lista }

/// Pantalla principal del comprador.
///
/// Causa raíz del teclado "fantasma" (corregida): antes esta pantalla tenía un
/// TextField permanente. Cuando ese campo había tenido foco alguna vez,
/// Flutter lo restauraba al volver de modales (filtros, orden) o de otras
/// rutas (perfil), abriendo el teclado y reacomodando todo. Ahora Descubrir NO
/// contiene ningún campo de texto: la búsqueda vive en [SearchScreen], una
/// ruta aparte. Sin campo enfocable no hay foco que restaurar.
///
/// Rendimiento: consulta Firestore por páginas. Recalcula la lista solo en momentos
/// seguros (aplicar búsqueda/filtros/orden, volver de un detalle o reactivar
/// la pestaña) y únicamente si el catálogo cambió (`catalogRevision`); jamás
/// en mitad de un swipe, para no desordenar el mazo.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  ModoDescubrimiento _modo = ModoDescubrimiento.tarjetas;
  DiscoverFilters _filtros = const DiscoverFilters();
  final List<CoffeeLot> _acumulados = []; // lotes publicados ya descargados
  List<CoffeeLot> _lotes = []; // visibles tras filtros, exclusiones y orden
  dynamic _cursor;
  bool _hayMas = true;
  bool _cargando = true;
  RepoException? _error;
  int _versionMazo = 0; // cambia en cada recarga para reiniciar el CardSwiper limpio
  String _firmaCargada = '';
  bool _inicializado = false;
  // Estado anterior de la pestaña (Descubrir = índice 0). Empieza en true: la
  // primera carga ya la hace didChangeDependencies, y solo al volver desde
  // otra pestaña se revisa si el catálogo cambió.
  bool _pestanaActivaAnterior = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inicializado) {
      _inicializado = true;
      _cargar(reiniciar: true);
    }
  }

  String _firma() {
    final a = context.read<ActivityProvider>();
    return '${a.lotesYaSolicitados.length}|${a.descartes.length}';
  }

  /// Descarga páginas de lotes publicados hasta reunir una lista útil
  /// (máx. 5 páginas por pulsación) y recalcula la lista visible.
  Future<void> _cargar({required bool reiniciar}) async {
    final repo = context.read<CoffeeLotRepository>();
    if (reiniciar) {
      _acumulados.clear();
      _cursor = null;
      _hayMas = true;
      _error = null;
    }
    setState(() => _cargando = true);
    try {
      var rondas = 0;
      var utiles = _calcular().length;
      final meta = utiles + CoffeeLotRepository.tamanoPagina;
      while (_hayMas && rondas < 5 && utiles < meta) {
        final pagina = await repo.consultarCatalogo(orden: _filtros.orden, despuesDe: _cursor);
        if (!mounted) return;
        _acumulados.addAll(pagina.lotes);
        _cursor = pagina.cursor;
        _hayMas = pagina.hayMas;
        rondas++;
        utiles = _calcular().length;
      }
      _error = null;
    } on RepoException catch (e) {
      if (!mounted) return;
      if (_acumulados.isEmpty) {
        _error = e;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.danger));
      }
    }
    if (!mounted) return;
    setState(() {
      _lotes = _calcular();
      _firmaCargada = _firma();
      _versionMazo++;
      _cargando = false;
    });
  }

  List<CoffeeLot> _calcular() {
    final uid = context.read<SessionProvider>().usuario?.uid;
    final actividad = context.read<ActivityProvider>();
    final yaSolicitados = actividad.lotesYaSolicitados;
    final descartes = actividad.descartes;
    final filtrados = _acumulados
        .where((l) =>
            l.sellerId != uid &&
            !yaSolicitados.contains(l.id) &&
            !descartes.contains(l.id) &&
            CatalogLogic.coincide(l, _filtros))
        .toList();
    return CatalogLogic.ordenar(filtrados, _filtros.orden, context.read<SessionProvider>().usuario);
  }

  /// Lotes descargados visibles para este comprador, sin aplicar la búsqueda.
  List<CoffeeLot> _calcularBase() {
    final uid = context.read<SessionProvider>().usuario?.uid;
    final a = context.read<ActivityProvider>();
    return _acumulados
        .where((l) => l.sellerId != uid && !a.lotesYaSolicitados.contains(l.id) && !a.descartes.contains(l.id))
        .toList();
  }

  /// Recalcula sin volver a descargar (cambian filtros o exclusiones).
  void _recargar() {
    if (!mounted) return;
    setState(() {
      _lotes = _calcular();
      _firmaCargada = _firma();
      _versionMazo++;
    });
    if (_lotes.isEmpty && _hayMas && !_cargando) _cargar(reiniciar: false);
  }

  void _recargarSiCambio() {
    if (!mounted) return;
    if (_firma() != _firmaCargada) _recargar();
  }

  Future<void> _abrirBusqueda() async {
    liberarFoco();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          filtrosBase: _filtros,
          lotesBase: _calcularBase(),
          onQueryChanged: (q) => _filtros = _filtros.copyWith(busqueda: q),
        ),
      ),
    );
    if (!mounted) return;
    liberarFoco();
    _recargar();
  }

  Future<void> _abrirFiltros() async {
    liberarFoco();
    final resultado = await mostrarFiltros(context, _filtros);
    if (!mounted) return;
    liberarFoco();
    if (resultado != null) {
      _filtros = resultado;
      _recargar();
    }
  }

  Future<void> _elegirOrden() async {
    liberarFoco();
    final elegido = await showModalBottomSheet<DiscoverSort>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ordenar por', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            ...DiscoverSort.values.map((s) {
              final activo = s == _filtros.orden;
              return RadioListTile<DiscoverSort>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(s.label, style: TextStyle(fontWeight: activo ? FontWeight.w800 : FontWeight.w500)),
                value: s,
                groupValue: _filtros.orden,
                activeColor: AppColors.coffeeMedium,
                onChanged: (v) => Navigator.pop(context, v),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    liberarFoco();
    if (elegido != null && elegido != _filtros.orden) {
      // Firestore solo ordena por fecha o precio; otros órdenes se aplican
      // en el cliente sobre lo ya descargado.
      String ordenServidor(DiscoverSort o) =>
          o == DiscoverSort.precioAsc ? 'precioAsc' : (o == DiscoverSort.precioDesc ? 'precioDesc' : 'fecha');
      final cambiaServidor = ordenServidor(elegido) != ordenServidor(_filtros.orden);
      _filtros = _filtros.copyWith(orden: elegido);
      if (cambiaServidor) {
        _cargar(reiniciar: true);
      } else {
        _recargar();
      }
    }
  }

  void _limpiarFiltros() {
    _filtros = DiscoverFilters(busqueda: _filtros.busqueda, orden: _filtros.orden);
    _recargar();
  }

  void _limpiarBusqueda() {
    _filtros = _filtros.copyWith(busqueda: '');
    _recargar();
  }

  /// Filtro activo -> cómo quitarlo (solo ese grupo; la búsqueda y el orden se conservan).
  DiscoverFilters _sin({
    bool departamentos = false,
    bool variedades = false,
    bool procesos = false,
    bool certificaciones = false,
    bool precio = false,
    bool altitud = false,
    bool puntaje = false,
    bool tipo = false,
    bool disponibles = false,
    bool verificados = false,
  }) {
    final f = _filtros;
    return DiscoverFilters(
      departamentos: departamentos ? const [] : f.departamentos,
      variedades: variedades ? const [] : f.variedades,
      procesos: procesos ? const [] : f.procesos,
      certificaciones: certificaciones ? const [] : f.certificaciones,
      precioMinCOP: precio ? null : f.precioMinCOP,
      precioMaxCOP: precio ? null : f.precioMaxCOP,
      altitudMin: altitud ? null : f.altitudMin,
      altitudMax: altitud ? null : f.altitudMax,
      puntajeMin: puntaje ? null : f.puntajeMin,
      tipoCafe: tipo ? null : f.tipoCafe,
      soloDisponibles: disponibles ? false : f.soloDisponibles,
      soloVerificados: verificados ? false : f.soloVerificados,
      busqueda: f.busqueda,
      orden: f.orden,
    );
  }

  void _aplicarFiltros(DiscoverFilters nuevos) {
    _filtros = nuevos;
    _recargar();
  }

  /// Un chip por grupo de filtro activo, para ver de un vistazo qué está
  /// filtrando el catálogo y quitarlo con un toque.
  List<Widget> _chipsActivos() {
    String resumen(List<String> v) => v.length == 1 ? v.first : '${v.first} +${v.length - 1}';
    final f = _filtros;
    final chips = <Widget>[];
    void add(String etiqueta, VoidCallback onQuitar) => chips.add(_ChipActivo(etiqueta: etiqueta, onQuitar: onQuitar));

    if (f.hayBusqueda) add('“${f.busqueda.trim()}”', _limpiarBusqueda);
    if (f.departamentos.isNotEmpty) add(resumen(f.departamentos), () => _aplicarFiltros(_sin(departamentos: true)));
    if (f.variedades.isNotEmpty) add(resumen(f.variedades), () => _aplicarFiltros(_sin(variedades: true)));
    if (f.procesos.isNotEmpty) add(resumen(f.procesos), () => _aplicarFiltros(_sin(procesos: true)));
    if (f.tipoCafe != null) add(f.tipoCafe!, () => _aplicarFiltros(_sin(tipo: true)));
    if (f.precioMinCOP != null || f.precioMaxCOP != null) add('Precio', () => _aplicarFiltros(_sin(precio: true)));
    if (f.altitudMin != null || f.altitudMax != null) add('Altitud', () => _aplicarFiltros(_sin(altitud: true)));
    if (f.puntajeMin != null) add('Puntaje ≥ ${f.puntajeMin!.toStringAsFixed(0)}', () => _aplicarFiltros(_sin(puntaje: true)));
    if (f.certificaciones.isNotEmpty) add(resumen(f.certificaciones), () => _aplicarFiltros(_sin(certificaciones: true)));
    if (f.soloDisponibles) add('Disponibles', () => _aplicarFiltros(_sin(disponibles: true)));
    if (f.soloVerificados) add('Verificados', () => _aplicarFiltros(_sin(verificados: true)));
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    // Al volver a la pestaña Descubrir se revisa (una vez) si el catálogo cambió.
    final activa = context.select<HomeTabNotifier, bool>((t) => t.indice == 0);
    if (activa && !_pestanaActivaAnterior) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recargarSiCambio());
    }
    _pestanaActivaAnterior = activa;

    final nFiltros = _filtros.numFiltrosActivos;
    final hayBusqueda = _filtros.hayBusqueda;
    final textTheme = Theme.of(context).textTheme;
    final chipsActivos = _chipsActivos();

    return Scaffold(
      // Descubrir no contiene campos de texto: el teclado nunca debe
      // reacomodar su layout, y la tarjeta conserva posición y escala.
      // (La búsqueda, que sí usa teclado, es otra ruta con su propio Scaffold.)
      resizeToAvoidBottomInset: false,
      // Sin AppBar: el título y los controles comparten un encabezado
      // compacto que deja más altura a las fotografías.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Descubrir café', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.headlineSmall),
                  ),
                  const SizedBox(width: 12),
                  _SelectorModo(modo: _modo, onChanged: (m) => setState(() => _modo = m)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(child: _CampoBusqueda(onTap: _abrirBusqueda)),
                  const SizedBox(width: 8),
                  _BotonIcono(
                    icono: Icons.tune,
                    tooltip: 'Filtrar',
                    activo: nFiltros > 0,
                    contador: nFiltros,
                    onTap: _abrirFiltros,
                  ),
                  const SizedBox(width: 8),
                  _BotonIcono(
                    icono: Icons.sort,
                    tooltip: 'Ordenar',
                    activo: _filtros.orden != DiscoverSort.relevancia,
                    onTap: _elegirOrden,
                  ),
                ],
              ),
            ),
            if (chipsActivos.isNotEmpty)
              SizedBox(
                // Crece con el tamaño de letra del sistema para no recortar los chips.
                height: 50 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0).toDouble(),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  children: [
                    for (final chip in chipsActivos) ...[chip, const SizedBox(width: 8)],
                    if (nFiltros > 1 || (nFiltros > 0 && hayBusqueda))
                      TextButton(
                        onPressed: _limpiarFiltros,
                        style: TextButton.styleFrom(minimumSize: const Size(48, 34), padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('Limpiar filtros', style: TextStyle(fontSize: 12.5)),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
            Expanded(
              child: (_cargando && _acumulados.isEmpty)
                  ? const Center(child: CircularProgressIndicator(color: AppColors.coffeeMedium))
                  : (_error != null && _acumulados.isEmpty)
                      ? RepoErrorView(error: _error!, onReintentar: () => _cargar(reiniciar: true))
                      : (_acumulados.isEmpty && !_hayMas)
                          ? const EmptyState(
                              icono: Icons.coffee_outlined,
                              titulo: 'Todavía no hay cafés publicados',
                              subtitulo: 'Cuando los productores publiquen sus lotes, podrás descubrirlos aquí.',
                            )
                          : _lotes.isEmpty
                              ? _EstadoVacio(
                                  hayMas: _hayMas,
                                  cargando: _cargando,
                                  onCargarMas: () => _cargar(reiniciar: false),
                                  hayBusqueda: hayBusqueda,
                                  hayFiltros: nFiltros > 0,
                                  consulta: _filtros.busqueda.trim(),
                                  onLimpiarFiltros: _limpiarFiltros,
                                  onLimpiarBusqueda: _limpiarBusqueda,
                                  onVerGuardados: () => context.read<HomeTabNotifier>().ir(2),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _modo == ModoDescubrimiento.tarjetas
                                      ? SwipeModeView(
                                          key: ValueKey('mazo_$_versionMazo'),
                                          lotes: _lotes,
                                          onCambioLista: () => setState(() => _modo = ModoDescubrimiento.lista),
                                          onRegresoDeDetalle: _recargarSiCambio,
                                        )
                                      : ListModeView(
                                          key: ValueKey('lista_$_versionMazo'),
                                          lotes: _lotes,
                                          onRegresoDeDetalle: _recargarSiCambio,
                                        ),
                                ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acceso a la búsqueda. Parece un campo pero es un botón: Descubrir no
/// contiene ningún TextField (ver la nota de la clase principal).
class _CampoBusqueda extends StatelessWidget {
  final VoidCallback onTap;
  const _CampoBusqueda({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Buscar café',
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlBorder,
          side: const BorderSide(color: AppColors.outline),
        ),
        child: InkWell(
          borderRadius: AppRadius.controlBorder,
          onTap: onTap,
          child: const SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: AppColors.coffeeMedium),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Buscar café, variedad o finca',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón cuadrado de icono (Filtrar / Ordenar). Activo = relleno marrón; en
/// Filtrar muestra además cuántos grupos de filtro hay aplicados.
class _BotonIcono extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final bool activo;
  final int contador;
  final VoidCallback onTap;

  const _BotonIcono({
    required this.icono,
    required this.tooltip,
    required this.activo,
    required this.onTap,
    this.contador = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: contador > 0 ? '$tooltip, $contador activos' : tooltip,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: activo ? AppColors.coffeeMedium : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.controlBorder,
                    side: BorderSide(color: activo ? AppColors.coffeeMedium : AppColors.outline),
                  ),
                  child: InkWell(
                    borderRadius: AppRadius.controlBorder,
                    onTap: onTap,
                    child: Icon(icono, size: 21, color: activo ? Colors.white : AppColors.coffeeDark),
                  ),
                ),
              ),
              if (contador > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.coffeeMedium, width: 1.4),
                    ),
                    child: Text('$contador', style: const TextStyle(color: AppColors.coffeeMedium, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtro aplicado: etiqueta + «x». Un toque lo quita.
class _ChipActivo extends StatelessWidget {
  final String etiqueta;
  final VoidCallback onQuitar;
  const _ChipActivo({required this.etiqueta, required this.onQuitar});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quitar $etiqueta',
      child: Material(
        color: AppColors.surfaceWarm,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onQuitar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.coffeeDark, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.close, size: 15, color: AppColors.inkSoft),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// Estados vacíos diferenciados: (1) sin resultados por filtros,
/// (2) sin resultados solo por búsqueda, (3) sin más cafés por descubrir.
class _EstadoVacio extends StatelessWidget {
  final bool hayBusqueda;
  final bool hayFiltros;
  final String consulta;
  final VoidCallback onLimpiarFiltros;
  final VoidCallback onLimpiarBusqueda;
  final VoidCallback onVerGuardados;
  final bool hayMas;
  final bool cargando;
  final VoidCallback onCargarMas;

  const _EstadoVacio({
    required this.hayMas,
    required this.cargando,
    required this.onCargarMas,
    required this.hayBusqueda,
    required this.hayFiltros,
    required this.consulta,
    required this.onLimpiarFiltros,
    required this.onLimpiarBusqueda,
    required this.onVerGuardados,
  });

  @override
  Widget build(BuildContext context) {
    late final String titulo;
    late final String detalle;
    late final IconData icono;
    final acciones = <Widget>[];

    if (hayFiltros) {
      icono = Icons.filter_alt_off_outlined;
      titulo = 'No encontramos cafés con esos criterios';
      detalle = 'Prueba eliminando un filtro o cambia la búsqueda.';
      acciones.add(_accion('Limpiar filtros', onLimpiarFiltros, principal: true));
      if (hayBusqueda) acciones.add(_accion('Limpiar búsqueda', onLimpiarBusqueda));
    } else if (hayBusqueda) {
      icono = Icons.search_off_outlined;
      titulo = 'Sin resultados para “$consulta”';
      detalle = 'Revisa la ortografía o prueba con otra variedad, finca o región.';
      acciones.add(_accion('Limpiar búsqueda', onLimpiarBusqueda, principal: true));
    } else {
      icono = Icons.coffee_outlined;
      titulo = 'Ya viste todos los cafés disponibles';
      detalle = 'Los vendedores publican lotes nuevos con frecuencia. Mientras tanto, revisa los que guardaste.';
      acciones.add(_accion('Ver guardados', onVerGuardados, principal: true));
    }

    if (hayMas) {
      acciones.add(_accion(cargando ? 'Buscando…' : 'Buscar más cafés', cargando ? () {} : onCargarMas));
    }
    // Con teléfonos pequeños la composición completa puede no caber: se
    // permite desplazarla en lugar de desbordar.
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: EmptyState(icono: icono, titulo: titulo, subtitulo: detalle, acciones: acciones),
        ),
      ),
    );
  }

  Widget _accion(String texto, VoidCallback onTap, {bool principal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: principal
          ? ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(200, 46)), onPressed: onTap, child: Text(texto))
          : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(200, 46)), onPressed: onTap, child: Text(texto)),
    );
  }
}

/// Selector Tarjetas | Lista de solo iconos: ocupa poco y se entiende sin
/// texto (el significado va en la etiqueta accesible y el tooltip).
class _SelectorModo extends StatelessWidget {
  final ModoDescubrimiento modo;
  final ValueChanged<ModoDescubrimiento> onChanged;

  const _SelectorModo({required this.modo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _opcion(ModoDescubrimiento.tarjetas, Icons.style_outlined, 'Tarjetas'),
          _opcion(ModoDescubrimiento.lista, Icons.view_agenda_outlined, 'Lista'),
        ],
      ),
    );
  }

  Widget _opcion(ModoDescubrimiento valor, IconData icono, String texto) {
    final activo = modo == valor;
    return Tooltip(
      message: texto,
      child: Semantics(
        button: true,
        selected: activo,
        label: 'Modo $texto',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control - 3),
          onTap: () => onChanged(valor),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: activo ? AppColors.coffeeMedium : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control - 3),
            ),
            child: Icon(icono, size: 19, color: activo ? Colors.white : AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}
