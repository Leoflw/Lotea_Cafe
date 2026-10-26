import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/mock_store.dart';
import '../../models/coffee_lot.dart';
import '../../services/session_provider.dart';
import '../../theme/app_theme.dart';
import '../requests/my_requests_screen.dart';
import '../saved/saved_screen.dart';
import 'filters_sheet.dart';
import 'list_mode_view.dart';
import 'swipe_mode_view.dart';

enum ModoDescubrimiento { tarjetas, lista }

/// Pantalla principal del comprador: descubrir vendedores/cafés. Incluye
/// buscador, filtros y ordenamiento (secciones 9-11 de la 2ª ronda) y un
/// encabezado con accesos rápidos (sección 22). El swipe es un mecanismo
/// de descubrimiento entre dos, no el centro de la app.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  ModoDescubrimiento _modo = ModoDescubrimiento.tarjetas;
  DiscoverFilters _filtros = const DiscoverFilters();
  final _busquedaCtrl = TextEditingController();
  List<CoffeeLot> _lotes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    final store = context.read<MockStore>();
    final uid = context.read<SessionProvider>().usuario!.uid;
    setState(() {
      _lotes = store.descubrirLotes(compradorId: uid, filtros: _filtros);
    });
  }

  Future<void> _abrirFiltros() async {
    final resultado = await mostrarFiltros(context, _filtros);
    if (resultado != null) {
      _filtros = resultado;
      _cargar();
    }
  }

  void _limpiarFiltros() {
    setState(() {
      _filtros = DiscoverFilters(busqueda: _filtros.busqueda, orden: _filtros.orden);
    });
    _cargar();
  }

  Future<void> _elegirOrden() async {
    final elegido = await showModalBottomSheet<DiscoverSort>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: DiscoverSort.values
              .map((s) => RadioListTile<DiscoverSort>(
                    title: Text(s.label),
                    value: s,
                    groupValue: _filtros.orden,
                    activeColor: AppColors.coffeeMedium,
                    onChanged: (v) => Navigator.pop(context, v),
                  ))
              .toList(),
        ),
      ),
    );
    if (elegido != null) {
      _filtros = _filtros.copyWith(orden: elegido);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<MockStore>(); // refresca tras crear solicitud/descarte

    final filtrosSinContarBusqueda = _filtros.tieneFiltrosActivos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Descubrir café'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            tooltip: 'Guardados',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.outbox_outlined),
            tooltip: 'Mis solicitudes',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Encuentra tu próximo café', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Desliza, filtra o busca por variedad, finca o región.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por café, variedad, finca o región…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busquedaCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _busquedaCtrl.clear();
                              _filtros = _filtros.copyWith(busqueda: '');
                              _cargar();
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    _filtros = _filtros.copyWith(busqueda: v);
                    _cargar();
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _abrirFiltros,
                        icon: Icon(Icons.tune, size: 18, color: filtrosSinContarBusqueda ? AppColors.coffeeMedium : null),
                        label: Text(filtrosSinContarBusqueda ? 'Filtros activos' : 'Filtrar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _elegirOrden,
                        icon: const Icon(Icons.sort, size: 18),
                        label: const Text('Ordenar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_lotes.length} cafés encontrados', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    if (filtrosSinContarBusqueda)
                      TextButton(onPressed: _limpiarFiltros, child: const Text('Limpiar filtros')),
                  ],
                ),
                const SizedBox(height: 6),
                _SelectorModo(modo: _modo, onChanged: (m) => setState(() => _modo = m)),
                const SizedBox(height: 6),
              ],
            ),
          ),
          Expanded(
            child: _lotes.isEmpty
                ? _SinResultados(hayFiltros: filtrosSinContarBusqueda || _filtros.busqueda.isNotEmpty, onLimpiar: _limpiarFiltros)
                : _modo == ModoDescubrimiento.tarjetas
                    ? SwipeModeView(lotes: _lotes, onCambioLista: () => setState(() => _modo = ModoDescubrimiento.lista))
                    : ListModeView(lotes: _lotes),
          ),
        ],
      ),
    );
  }
}

class _SinResultados extends StatelessWidget {
  final bool hayFiltros;
  final VoidCallback onLimpiar;
  const _SinResultados({required this.hayFiltros, required this.onLimpiar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.coffee_outlined, size: 56, color: AppColors.coffeeLight),
            const SizedBox(height: 16),
            const Text('No encontramos cafés con esos criterios', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              hayFiltros ? 'Prueba eliminando algún filtro o cambia tu búsqueda.' : 'Vuelve más tarde por nuevos cafés.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (hayFiltros) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onLimpiar, child: const Text('Limpiar filtros')),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectorModo extends StatelessWidget {
  final ModoDescubrimiento modo;
  final ValueChanged<ModoDescubrimiento> onChanged;

  const _SelectorModo({required this.modo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.coffeeLight),
      ),
      child: Row(
        children: [
          _opcion(context, ModoDescubrimiento.tarjetas, Icons.style_outlined, 'Tarjetas'),
          _opcion(context, ModoDescubrimiento.lista, Icons.view_list_outlined, 'Lista'),
        ],
      ),
    );
  }

  Widget _opcion(BuildContext context, ModoDescubrimiento valor, IconData icono, String texto) {
    final activo = modo == valor;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: activo ? AppColors.coffeeMedium : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 17, color: activo ? Colors.white : AppColors.coffeeDark),
              const SizedBox(width: 6),
              Text(texto, style: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
