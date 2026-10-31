import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/discover_filters.dart';
import '../../utils/catalog_logic.dart';
import '../../models/coffee_lot.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/focus_utils.dart';
import '../../widgets/coffee_lot_card.dart';
import '../seller/seller_detail_screen.dart';

/// Pantalla de búsqueda INDEPENDIENTE de Descubrir.
///
/// Es el único lugar del flujo de descubrimiento con un TextField. Así el
/// teclado solo existe mientras la persona está aquí, y Descubrir no tiene
/// ningún campo enfocable que Flutter pueda "restaurar" al volver de un
/// modal o de otra ruta (esa restauración de foco era la causa del teclado
/// que aparecía solo).
///
/// El texto se comunica a Descubrir por [onQueryChanged] en cada cambio, sin
/// reconstruir Descubrir mientras está oculta. Al cerrar por cualquier vía
/// (X, atrás del sistema, "Ver resultados") Descubrir ya tiene el texto y
/// recarga una sola vez.
class SearchScreen extends StatefulWidget {
  final DiscoverFilters filtrosBase;
  final List<CoffeeLot> lotesBase;
  final ValueChanged<String> onQueryChanged;

  const SearchScreen({super.key, required this.filtrosBase, required this.lotesBase, required this.onQueryChanged});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _sugerencias = ['Geisha', 'Huila', 'Honey', 'Caturra', 'Nariño'];

  late final TextEditingController _ctrl = TextEditingController(text: widget.filtrosBase.busqueda);
  final FocusNode _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  @override
  void dispose() {
    _foco.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String get _query => _ctrl.text.trim();

  List<CoffeeLot> _resultados(BuildContext context) {
    final filtros = widget.filtrosBase.copyWith(busqueda: _query);
    final res = widget.lotesBase.where((l) => CatalogLogic.coincide(l, filtros)).toList();
    return CatalogLogic.ordenar(res, filtros.orden, context.read<SessionProvider>().usuario);
  }

  void _cambio(String texto) {
    widget.onQueryChanged(texto.trim());
    setState(() {});
  }

  void _limpiar() {
    _ctrl.clear();
    widget.onQueryChanged('');
    setState(() {});
    _foco.requestFocus(); // limpiar es una acción del usuario dentro del buscador
  }

  void _usarSugerencia(String texto) {
    _ctrl.text = texto;
    _ctrl.selection = TextSelection.collapsed(offset: texto.length);
    widget.onQueryChanged(texto);
    liberarFoco();
    setState(() {});
  }

  void _cerrar() {
    liberarFoco();
    Navigator.of(context).maybePop();
  }

  Future<void> _abrirDetalle(CoffeeLot lote) async {
    liberarFoco();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SellerDetailScreen(sellerId: lote.sellerId, loteDestacadoId: lote.id)),
    );
    if (mounted) {
      liberarFoco();
      setState(() {}); // los resultados pueden haber cambiado (p. ej. solicitud enviada)
    }
  }

  @override
  Widget build(BuildContext context) {
    // Esta pantalla SÍ debe reaccionar al teclado (resizeToAvoidBottomInset
    // por defecto): la lista de resultados se acorta y nada queda tapado.
    final resultados = _resultados(context);
    final hayTexto = _query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Cerrar búsqueda',
          onPressed: _cerrar,
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _foco,
          autofocus: true, // el teclado se abre aquí porque la persona eligió buscar
          textInputAction: TextInputAction.search,
          onChanged: _cambio,
          onSubmitted: (_) => liberarFoco(), // "Buscar" en el teclado lo oculta y deja ver los resultados
          decoration: const InputDecoration(
            hintText: 'Buscar por café, variedad, finca…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (hayTexto)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Borrar texto',
              onPressed: _limpiar,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hayTexto ? '${resultados.length} ${resultados.length == 1 ? 'café encontrado' : 'cafés encontrados'}' : 'Escribe para buscar en el catálogo',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: !hayTexto
                ? _Sugerencias(sugerencias: _sugerencias, onTap: _usarSugerencia)
                : resultados.isEmpty
                    ? _SinResultadosBusqueda(query: _query, onLimpiar: _limpiar)
                    : ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: resultados.length,
                        itemBuilder: (context, i) => CoffeeLotCard(
                          lote: resultados[i],
                          onTap: () => _abrirDetalle(resultados[i]),
                        ),
                      ),
          ),
          if (hayTexto && resultados.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _cerrar,
                  child: Text('Ver ${resultados.length} en Descubrir'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sugerencias extends StatelessWidget {
  final List<String> sugerencias;
  final ValueChanged<String> onTap;
  const _Sugerencias({required this.sugerencias, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Prueba con', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sugerencias
                .map((s) => ActionChip(
                      label: Text(s),
                      avatar: const Icon(Icons.search, size: 16, color: AppColors.coffeeMedium),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.coffeeLight),
                      onPressed: () => onTap(s),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SinResultadosBusqueda extends StatelessWidget {
  final String query;
  final VoidCallback onLimpiar;
  const _SinResultadosBusqueda({required this.query, required this.onLimpiar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.coffee_outlined, size: 52, color: AppColors.coffeeLight),
            const SizedBox(height: 14),
            Text('Sin resultados para “$query”', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Revisa la ortografía o prueba con otra variedad, finca o región.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onLimpiar,
              child: const Text('Limpiar búsqueda'),
            ),
          ],
        ),
      ),
    );
  }
}
