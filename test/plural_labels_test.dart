import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/utils/format_utils.dart';

void main() {
  test('cafés publicados', () {
    expect(etiquetaCafesPublicados(0), '0 cafés publicados');
    expect(etiquetaCafesPublicados(1), '1 café publicado');
    expect(etiquetaCafesPublicados(2), '2 cafés publicados');
  });

  test('conexiones', () {
    expect(etiquetaConexiones(0), '0 conexiones');
    expect(etiquetaConexiones(1), '1 conexión');
    expect(etiquetaConexiones(2), '2 conexiones');
  });

  test('solicitudes pendientes', () {
    expect(etiquetaSolicitudesPendientes(0), '0 solicitudes pendientes');
    expect(etiquetaSolicitudesPendientes(1), '1 solicitud pendiente');
    expect(etiquetaSolicitudesPendientes(3), '3 solicitudes pendientes');
  });

  test('cotizaciones y fotos', () {
    expect(etiquetaCotizaciones(1), '1 cotización');
    expect(etiquetaCotizaciones(4), '4 cotizaciones');
    expect(etiquetaFotos(1), '1 foto');
    expect(etiquetaFotos(5), '5 fotos');
  });

  test('pluralizar genérico', () {
    expect(pluralizar(1, 'foto', 'fotos'), '1 foto');
    expect(pluralizar(0, 'foto', 'fotos'), '0 fotos');
  });
}
