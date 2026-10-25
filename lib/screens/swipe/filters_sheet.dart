import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SwipeFilters {
  final List<String> variedades;
  final double? precioMax;
  final String? proceso;

  const SwipeFilters({this.variedades = const [], this.precioMax, this.proceso});

  SwipeFilters copyWith({
    List<String>? variedades,
    double? precioMax,
    String? proceso,
  }) {
    return SwipeFilters(
      variedades: variedades ?? this.variedades,
      precioMax: precioMax ?? this.precioMax,
      proceso: proceso ?? this.proceso,
    );
  }
}

const List<String> variedadesDisponibles = [
  'Arábica',
  'Robusta',
  'Geisha',
  'Bourbon',
  'Typica',
  'Caturra',
];

const List<String> procesosDisponibles = [
  'Lavado',
  'Natural',
  'Honey',
];

/// Muestra el bottom sheet y devuelve los filtros elegidos (o null si se
/// cancela). Corresponde a "Búsqueda/filtros" de la sección 2.3.
Future<SwipeFilters?> mostrarFiltros(
  BuildContext context,
  SwipeFilters actuales,
) {
  var variedadesSel = List<String>.from(actuales.variedades);
  var procesoSel = actuales.proceso;
  var precioMax = actuales.precioMax ?? 50.0;

  return showModalBottomSheet<SwipeFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text('Filtros de búsqueda',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  const Text('Variedad', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: variedadesDisponibles.map((v) {
                      final activo = variedadesSel.contains(v);
                      return FilterChip(
                        label: Text(v),
                        selected: activo,
                        selectedColor: AppColors.coffeeMedium,
                        labelStyle: TextStyle(
                          color: activo ? Colors.white : AppColors.coffeeDark,
                        ),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              variedadesSel.add(v);
                            } else {
                              variedadesSel.remove(v);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('Proceso', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: procesosDisponibles.map((p) {
                      final activo = procesoSel == p;
                      return ChoiceChip(
                        label: Text(p),
                        selected: activo,
                        selectedColor: AppColors.leafGreen,
                        labelStyle: TextStyle(
                          color: activo ? Colors.white : AppColors.coffeeDark,
                        ),
                        onSelected: (sel) {
                          setState(() => procesoSel = sel ? p : null);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text('Precio máximo: \$${precioMax.toStringAsFixed(0)}/kg',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: precioMax,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    activeColor: AppColors.coffeeMedium,
                    label: '\$${precioMax.toStringAsFixed(0)}',
                    onChanged: (v) => setState(() => precioMax = v),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        SwipeFilters(
                          variedades: variedadesSel,
                          proceso: procesoSel,
                          precioMax: precioMax,
                        ),
                      );
                    },
                    child: const Text('Aplicar filtros'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
