import 'package:flutter/material.dart';
import '../../utils/focus_utils.dart';
import '../../models/discover_filters.dart';
import '../../models/coffee_lot.dart';
import '../../models/seller_profile.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';

/// Bottom sheet de filtros ampliado (sección 14 del plan de evolución).
/// Devuelve un [DiscoverFilters] o null si el usuario cancela.
Future<DiscoverFilters?> mostrarFiltros(BuildContext context, DiscoverFilters actuales) {
  liberarFoco();
  var deptos = List<String>.from(actuales.departamentos);
  var variedades = List<String>.from(actuales.variedades);
  var procesos = List<String>.from(actuales.procesos);
  var certs = List<String>.from(actuales.certificaciones);
  var precioRange = RangeValues(
    actuales.precioMinCOP ?? 10000,
    actuales.precioMaxCOP ?? 100000,
  );
  var altitudRange = RangeValues(
    actuales.altitudMin ?? 900,
    actuales.altitudMax ?? 2100,
  );
  var puntajeMin = actuales.puntajeMin ?? 75;
  var soloDisponibles = actuales.soloDisponibles;
  var soloVerificados = actuales.soloVerificados;
  var tipoCafe = actuales.tipoCafe;

  return showModalBottomSheet<DiscoverFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
                        TextButton(
                          onPressed: () => setState(() {
                            deptos = [];
                            variedades = [];
                            procesos = [];
                            certs = [];
                            precioRange = const RangeValues(10000, 100000);
                            altitudRange = const RangeValues(900, 2100);
                            puntajeMin = 75;
                            soloDisponibles = false;
                            soloVerificados = false;
                            tipoCafe = null;
                          }),
                          child: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    _titulo('Departamento'),
                    _chips(departamentosColombia, deptos, (v, sel) => setState(
                        () => sel ? deptos.add(v) : deptos.remove(v))),
                    _titulo('Variedad'),
                    _chips(variedadesDisponibles, variedades, (v, sel) => setState(
                        () => sel ? variedades.add(v) : variedades.remove(v))),
                    _titulo('Proceso'),
                    _chips(procesosDisponibles, procesos, (v, sel) => setState(
                        () => sel ? procesos.add(v) : procesos.remove(v))),
                    _titulo('Tipo de café'),
                    Wrap(
                      spacing: 8,
                      children: tiposCafeDisponibles.map((t) {
                        final activo = tipoCafe == t;
                        return ChoiceChip(
                          label: Text(t),
                          selected: activo,
                          selectedColor: AppColors.leafGreen,
                          labelStyle: TextStyle(color: activo ? Colors.white : AppColors.coffeeDark),
                          onSelected: (_) => setState(() => tipoCafe = activo ? null : t),
                        );
                      }).toList(),
                    ),
                    _titulo('Precio (${formatCOP(precioRange.start)} — ${formatCOP(precioRange.end)} / kg)'),
                    RangeSlider(
                      values: precioRange,
                      min: 10000,
                      max: 100000,
                      divisions: 18,
                      activeColor: AppColors.coffeeMedium,
                      labels: RangeLabels(formatCOP(precioRange.start), formatCOP(precioRange.end)),
                      onChanged: (v) => setState(() => precioRange = v),
                    ),
                    _titulo(
                        'Altitud (${altitudRange.start.round()} — ${altitudRange.end.round()} msnm)'),
                    RangeSlider(
                      values: altitudRange,
                      min: 900,
                      max: 2100,
                      divisions: 24,
                      activeColor: AppColors.coffeeMedium,
                      onChanged: (v) => setState(() => altitudRange = v),
                    ),
                    _titulo('Puntaje mínimo de taza (${puntajeMin.toStringAsFixed(0)})'),
                    Slider(
                      value: puntajeMin,
                      min: 75,
                      max: 95,
                      divisions: 20,
                      activeColor: AppColors.coffeeMedium,
                      label: puntajeMin.toStringAsFixed(0),
                      onChanged: (v) => setState(() => puntajeMin = v),
                    ),
                    _titulo('Certificaciones'),
                    _chips(certificacionesDisponibles, certs, (v, sel) => setState(
                        () => sel ? certs.add(v) : certs.remove(v))),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Solo lotes disponibles'),
                      value: soloDisponibles,
                      activeThumbColor: AppColors.coffeeMedium,
                      onChanged: (v) => setState(() => soloDisponibles = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Solo vendedores verificados'),
                      value: soloVerificados,
                      activeThumbColor: AppColors.coffeeMedium,
                      onChanged: (v) => setState(() => soloVerificados = v),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(DiscoverFilters(
                          departamentos: deptos,
                          variedades: variedades,
                          procesos: procesos,
                          certificaciones: certs,
                          // Un rango/valor sin tocar (en su extremo por defecto)
                          // NO es un filtro: se devuelve null para que el
                          // contador de filtros activos sea veraz.
                          precioMinCOP: precioRange.start > 10000 ? precioRange.start : null,
                          precioMaxCOP: precioRange.end < 100000 ? precioRange.end : null,
                          altitudMin: altitudRange.start > 900 ? altitudRange.start : null,
                          altitudMax: altitudRange.end < 2100 ? altitudRange.end : null,
                          puntajeMin: puntajeMin > 75 ? puntajeMin : null,
                          soloDisponibles: soloDisponibles,
                          soloVerificados: soloVerificados,
                          tipoCafe: tipoCafe,
                          busqueda: actuales.busqueda,
                          orden: actuales.orden,
                        ));
                      },
                      child: const Text('Aplicar filtros'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

Widget _titulo(String texto) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
    );

Widget _chips(List<String> opciones, List<String> seleccionados, void Function(String, bool) onToggle) {
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
        onSelected: (sel) => onToggle(op, sel),
      );
    }).toList(),
  );
}
