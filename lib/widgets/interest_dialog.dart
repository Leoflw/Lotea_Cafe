import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/coffee_lot.dart';
import '../repositories/interest_request_repository.dart';
import '../repositories/repo_exception.dart';
import '../services/home_tab_notifier.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/focus_utils.dart';

/// Confirma y envía una solicitud de contacto ("Me interesa"). Devuelve
/// `true` si la solicitud se envió, `false` si el usuario canceló o ya
/// existía una — así el swipe puede deshacer la tarjeta cuando no se envió.
/// Tras enviar muestra una confirmación breve con acción "Ver solicitudes"
/// que lleva a la pestaña Solicitudes (sin abrir rutas paralelas).
Future<bool> mostrarDialogoInteres({
  required BuildContext context,
  required CoffeeLot lote,
}) async {
  liberarFoco();
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Enviar solicitud de contacto'),
      content: Text(
        'Se enviará una solicitud comercial al vendedor por "${lote.nombre}". '
        'Si la acepta, se habilitará el chat para que puedan negociar directamente.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Me interesa'),
        ),
      ],
    ),
  );

  if (confirmar != true || !context.mounted) return false;

  // Se capturan antes del await/snackbar: el contexto puede desmontarse
  // (p. ej. al cerrar el detalle) antes de que se pulse la acción.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final tabs = context.read<HomeTabNotifier>();
  final repo = context.read<InterestRequestRepository>();
  final comprador = context.read<SessionProvider>().usuario;
  if (comprador == null) return false;

  try {
    // Solo se muestra «Solicitud enviada» cuando Firestore la confirmó.
    await repo.crear(comprador: comprador, lote: lote);
  } on RepoException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(e.mensaje),
      backgroundColor: e.tipo == RepoErrorKind.duplicado ? AppColors.coffeeMedium : AppColors.danger,
    ));
    return false;
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Solicitud enviada'),
      backgroundColor: AppColors.leafGreen,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Ver solicitudes',
        textColor: Colors.white,
        onPressed: () {
          navigator.popUntil((r) => r.isFirst);
          tabs.ir(1);
        },
      ),
    ),
  );
  return true;
}
