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
