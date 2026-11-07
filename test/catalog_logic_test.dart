import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/discover_filters.dart';
import 'package:lotea_cafe/utils/catalog_logic.dart';

CoffeeLot lote({
  String id = 'l1',
  String nombre = 'Lote Pitalito',
  List<String> variedades = const ['Caturra'],
  String proceso = 'Lavado',
  double precio = 30000,
  double? puntaje = 86,
  String departamento = 'Huila',
  bool disponible = true,
  EstadoLote estado = EstadoLote.publicado,
  DateTime? fecha,
}) {
  return CoffeeLot(
    id: id,
    sellerId: 's1',
    nombre: nombre,
    variedades: variedades,
    proceso: proceso,
    precioCOP: precio,
    puntajeTaza: puntaje,
    departamento: departamento,
    sellerNombreMarca: 'Finca La Esperanza',
    disponible: disponible,
    estado: estado,
    fechaPublicacion: fecha,
  );
}

AppUser comprador({BuyerPreferences prefs = const BuyerPreferences()}) => AppUser(
      uid: 'u1',
      email: 'a@b.co',
      nombre: 'Ana',
      rol: UserRole.comprador,
      preferencias: prefs,
    );

void main() {
  group('búsqueda y filtros', () {
    test('normaliza tildes y mayúsculas', () {
      expect(CatalogLogic.normalizar('Nariño'), 'narino');
    });

    test('la búsqueda encuentra por departamento sin tildes', () {
      final l = lote(departamento: 'Nariño');
      expect(CatalogLogic.coincide(l, const DiscoverFilters(busqueda: 'narino')), isTrue);
      expect(CatalogLogic.coincide(l, const DiscoverFilters(busqueda: 'huila')), isFalse);
    });

    test('nunca coincide un borrador', () {
      expect(CatalogLogic.coincide(lote(estado: EstadoLote.borrador), const DiscoverFilters()), isFalse);
    });

    test('filtra por precio máximo y disponibilidad', () {
      final caro = lote(precio: 90000);
      expect(CatalogLogic.coincide(caro, const DiscoverFilters(precioMaxCOP: 50000)), isFalse);
      expect(CatalogLogic.coincide(lote(disponible: false), const DiscoverFilters(soloDisponibles: true)), isFalse);
    });

    test('filtra por puntaje mínimo y excluye lotes sin puntaje', () {
      expect(CatalogLogic.coincide(lote(puntaje: null), const DiscoverFilters(puntajeMin: 85)), isFalse);
      expect(CatalogLogic.coincide(lote(puntaje: 87), const DiscoverFilters(puntajeMin: 85)), isTrue);
    });

    test('cuenta grupos de filtros activos', () {
      const f = DiscoverFilters(departamentos: ['Huila'], soloDisponibles: true, busqueda: 'x');
      expect(f.numFiltrosActivos, 2);
    });
  });

  group('orden y relevancia', () {
    test('ordena por precio ascendente', () {
      final r = CatalogLogic.ordenar(
        [lote(id: 'a', precio: 50000), lote(id: 'b', precio: 20000)],
        DiscoverSort.precioAsc,
        null,
      );
      expect(r.map((l) => l.id), ['b', 'a']);
    });

    test('ordena por más recientes', () {
      final r = CatalogLogic.ordenar(
        [lote(id: 'viejo', fecha: DateTime(2026, 1, 1)), lote(id: 'nuevo', fecha: DateTime(2026, 9, 1))],
        DiscoverSort.recientes,
        null,
      );
      expect(r.first.id, 'nuevo');
    });

    test('la relevancia premia las preferencias del comprador', () {
      final u = comprador(prefs: const BuyerPreferences(variedades: ['Geisha'], procesos: ['Natural']));
      final coincide = lote(id: 'g', variedades: const ['Geisha'], proceso: 'Natural');
      final otro = lote(id: 'c');
      expect(CatalogLogic.puntuar(coincide, u), greaterThan(CatalogLogic.puntuar(otro, u)));
      final r = CatalogLogic.ordenar([otro, coincide], DiscoverSort.relevancia, u);
      expect(r.first.id, 'g');
    });

    test('«coincide con tus preferencias» exige coincidencia sustancial', () {
      final u = comprador(prefs: const BuyerPreferences(variedades: ['Geisha'], procesos: ['Natural']));
      expect(CatalogLogic.coincideConPreferencias(lote(variedades: const ['Geisha'], proceso: 'Natural'), u), isTrue);
      // Solo 1 de 2 preferencias → no basta.
      expect(CatalogLogic.coincideConPreferencias(lote(variedades: const ['Geisha'], proceso: 'Lavado'), u), isFalse);
      // Sin preferencias nunca coincide.
      expect(CatalogLogic.coincideConPreferencias(lote(), comprador()), isFalse);
    });
  });

  group('serialización', () {
    test('CoffeeLot ida y vuelta conserva los datos', () {
      final original = lote(id: 'x', variedades: const ['Caturra', 'Castillo']);
      final mapa = original.toEditableMap();
      final copia = CoffeeLot.fromMap('x', mapa);
      expect(copia.nombre, original.nombre);
      expect(copia.variedades, original.variedades);
      expect(copia.precioCOP, original.precioCOP);
      expect(copia.estado, EstadoLote.publicado);
    });

    test('el cliente nunca escribe vendedorVerificado al editar', () {
      expect(lote().toEditableMap().containsKey('vendedorVerificado'), isFalse);
    });
  });
}
