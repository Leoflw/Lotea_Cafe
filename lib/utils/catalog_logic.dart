import '../models/app_user.dart';
import '../models/coffee_lot.dart';
import '../models/discover_filters.dart';

/// Lógica pura de filtrado, búsqueda, orden y relevancia sobre lotes ya
/// descargados. No toca Firebase, así que se prueba con datos de test.
class CatalogLogic {
  /// Minúsculas y sin tildes, para que "narino" encuentre "Nariño".
  static String normalizar(String texto) {
    const conTilde = 'áàäâéèëêíìïîóòöôúùüûñ';
    const sinTilde = 'aaaaeeeeiiiioooouuuun';
    final buffer = StringBuffer();
    for (final ch in texto.toLowerCase().split('')) {
      final i = conTilde.indexOf(ch);
      buffer.write(i == -1 ? ch : sinTilde[i]);
    }
    return buffer.toString();
  }

  static bool coincide(CoffeeLot l, DiscoverFilters f) {
    if (!l.publicado) return false;
    if (f.departamentos.isNotEmpty && !f.departamentos.contains(l.departamento)) return false;
    if (f.variedades.isNotEmpty && !l.variedades.any(f.variedades.contains)) return false;
    if (f.procesos.isNotEmpty && !f.procesos.contains(l.proceso)) return false;
    if (f.precioMinCOP != null && l.precioCOP < f.precioMinCOP!) return false;
    if (f.precioMaxCOP != null && l.precioCOP > f.precioMaxCOP!) return false;
    if (f.altitudMin != null && (l.altitudMsnm == null || l.altitudMsnm! < f.altitudMin!)) return false;
    if (f.altitudMax != null && (l.altitudMsnm == null || l.altitudMsnm! > f.altitudMax!)) return false;
    if (f.puntajeMin != null && (l.puntajeTaza == null || l.puntajeTaza! < f.puntajeMin!)) return false;
    if (f.certificaciones.isNotEmpty && !l.certificaciones.any(f.certificaciones.contains)) return false;
    if (f.soloDisponibles && !l.disponible) return false;
    if (f.tipoCafe != null && l.tipoCafe != f.tipoCafe) return false;
    if (f.soloVerificados && !l.vendedorVerificado) return false;

    final query = normalizar(f.busqueda.trim());
    if (query.isNotEmpty) {
      final texto = normalizar(
        '${l.nombre} ${l.variedades.join(' ')} ${l.proceso} ${l.tipoCafe ?? ''} '
        '${l.sellerNombreMarca} ${l.region} ${l.departamento} ${l.municipio}',
      );
      if (!texto.contains(query)) return false;
    }
    return true;
  }

  static DateTime _fecha(CoffeeLot l) => l.fechaPublicacion ?? DateTime.fromMillisecondsSinceEpoch(0);

  static List<CoffeeLot> ordenar(List<CoffeeLot> lotes, DiscoverSort orden, AppUser? comprador) {
    final copia = [...lotes];
    int cmp(CoffeeLot a, CoffeeLot b) {
      switch (orden) {
        case DiscoverSort.precioAsc:
          return a.precioCOP.compareTo(b.precioCOP);
        case DiscoverSort.precioDesc:
          return b.precioCOP.compareTo(a.precioCOP);
        case DiscoverSort.puntajeDesc:
          return (b.puntajeTaza ?? 0).compareTo(a.puntajeTaza ?? 0);
        case DiscoverSort.recientes:
          return _fecha(b).compareTo(_fecha(a));
        case DiscoverSort.disponibilidad:
          return (b.cantidadDisponibleKg ?? 0).compareTo(a.cantidadDisponibleKg ?? 0);
        case DiscoverSort.relevancia:
          if (comprador == null) return _fecha(b).compareTo(_fecha(a));
          final p = puntuar(b, comprador).compareTo(puntuar(a, comprador));
          return p != 0 ? p : _fecha(b).compareTo(_fecha(a));
      }
    }

    copia.sort(cmp);
    return copia;
  }

  /// Cuántas preferencias DIRECTAS (variedad, proceso, región) configuró el
  /// comprador y cuántas coinciden con el lote.
  static ({int configuradas, int coincidencias}) _directas(CoffeeLot lote, AppUser comprador) {
    final prefs = comprador.preferencias;
    int configuradas = 0;
    int coincidencias = 0;
    if (prefs.variedades.isNotEmpty) {
      configuradas++;
      if (lote.variedades.any(prefs.variedades.contains)) coincidencias++;
    }
    if (prefs.procesos.isNotEmpty) {
      configuradas++;
      if (prefs.procesos.contains(lote.proceso)) coincidencias++;
    }
    if (prefs.regiones.isNotEmpty) {
      configuradas++;
      if (prefs.regiones.contains(lote.departamento)) coincidencias++;
    }
    return (configuradas: configuradas, coincidencias: coincidencias);
  }

  /// Relevancia 0–100: 55 preferencias directas, 15 precio, 15 disponibilidad,
  /// 15 calidad (puntaje de taza 75–95). Sin IA: reglas sobre datos reales.
  static double puntuar(CoffeeLot lote, AppUser comprador) {
    final d = _directas(lote, comprador);
    final directo = d.configuradas == 0 ? 0.0 : 55.0 * d.coincidencias / d.configuradas;
    final maxPrecio = comprador.preferencias.precioMaxCOP;
    final precio = maxPrecio == null ? 7.5 : (lote.precioCOP <= maxPrecio ? 15.0 : 0.0);
    final disponibilidad = lote.disponible ? 15.0 : 0.0;
    final calidad = lote.puntajeTaza == null
        ? 0.0
        : 15.0 * ((lote.puntajeTaza! - 75) / 20).clamp(0.0, 1.0).toDouble();
    return directo + precio + disponibilidad + calidad;
  }

  /// Verdadero solo si coincide de forma sustancial con lo que el comprador
  /// configuró: disponible, dentro de su precio máximo y con TODAS sus
  /// preferencias (si configuró una) o al menos dos (si configuró varias).
  static bool coincideConPreferencias(CoffeeLot lote, AppUser comprador) {
    final d = _directas(lote, comprador);
    if (d.configuradas == 0 || d.coincidencias == 0) return false;
    if (!lote.disponible) return false;
    final maxPrecio = comprador.preferencias.precioMaxCOP;
    if (maxPrecio != null && lote.precioCOP > maxPrecio) return false;
    return d.configuradas == 1 || d.coincidencias >= 2;
  }
}
