/// Formato de moneda colombiana sin depender de datos de localización de
/// `intl` (que no siempre incluyen es_CO por defecto). Ej: 28000 -> "$28.000".
String formatCOP(num valor) {
  final entero = valor.round();
  final negativo = entero < 0;
  final digitos = entero.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digitos.length; i++) {
    final posDesdeElFinal = digitos.length - i;
    if (i > 0 && posDesdeElFinal % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return '${negativo ? '-' : ''}\$${buffer.toString()}';
}

String formatCOPPorUnidad(num valor, String unidad) => '${formatCOP(valor)} / $unidad';

String formatFecha(DateTime fecha) {
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${fecha.day} ${meses[fecha.month - 1]} ${fecha.year}';
}

/// Fecha que puede ser nula mientras el servidor confirma la escritura.
String formatFechaN(DateTime? fecha) => fecha == null ? 'Enviando…' : formatFecha(fecha);

String formatFechaHora(DateTime? fecha) {
  if (fecha == null) return 'Enviando…';
  final h = fecha.hour.toString().padLeft(2, '0');
  final m = fecha.minute.toString().padLeft(2, '0');
  return '${formatFecha(fecha)} · $h:$m';
}

/// Singular o plural según la cantidad: `pluralizar(1, 'conexión', 'conexiones')`
/// → `1 conexión`; `pluralizar(2, ...)` → `2 conexiones`; el 0 va en plural.
String pluralizar(int n, String singular, String plural) => '$n ${n == 1 ? singular : plural}';

String etiquetaCafesPublicados(int n) => n == 1 ? '1 café publicado' : '$n cafés publicados';
String etiquetaSolicitudesPendientes(int n) => n == 1 ? '1 solicitud pendiente' : '$n solicitudes pendientes';
String etiquetaConexiones(int n) => pluralizar(n, 'conexión', 'conexiones');
String etiquetaCotizaciones(int n) => pluralizar(n, 'cotización', 'cotizaciones');
String etiquetaFotos(int n) => pluralizar(n, 'foto', 'fotos');
