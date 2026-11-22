import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../state/session_provider.dart';

/// Mensaje único que explica por qué una acción comercial no está disponible.
const mensajeCuentaBloqueada =
    'Tu cuenta tiene una eliminación solicitada, así que las operaciones comerciales están bloqueadas. '
    'Puedes cancelar la solicitud en «Mi cuenta».';

/// Cuando la eliminación definitiva ya comenzó no hay nada que cancelar: no se menciona «Mi cuenta».
const mensajeCuentaEliminando =
    'Tu cuenta está en proceso de eliminación definitiva, así que las operaciones comerciales están bloqueadas.';

/// `true` (y avisa a la persona) si la cuenta no está activa. Se usa AL INICIO de cada acción
/// comercial. Es solo la explicación en pantalla: la protección real son las reglas de Firestore.
bool avisarSiCuentaBloqueada(BuildContext context) {
  final sesion = context.read<SessionProvider>();
  final bloqueada = sesion.operacionesBloqueadas;
  if (bloqueada) {
    final eliminando = sesion.usuario?.cuentaEstado == CuentaEstado.eliminando;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(eliminando ? mensajeCuentaEliminando : mensajeCuentaBloqueada), duration: const Duration(seconds: 6)));
  }
  return bloqueada;
}
