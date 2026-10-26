import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/mock_store.dart';
import '../models/coffee_lot.dart';
import '../theme/app_theme.dart';

/// Diálogo de confirmación de interés comercial ("Me interesa"). Crea la
/// [InterestRequest] correspondiente y explica el siguiente paso con
/// lenguaje comercial (nunca de citas). Si ya existe una solicitud para
/// el mismo café, avisa en vez de duplicarla (sección 14, 2ª ronda).
Future<void> mostrarDialogoInteres({
  required BuildContext context,
  required CoffeeLot lote,
  required String compradorId,
}) async {
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
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Me interesa'),
        ),
      ],
    ),
  );

  if (confirmar != true || !context.mounted) return;

  try {
    context.read<MockStore>().crearSolicitud(compradorId: compradorId, lote: lote);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Solicitud enviada. Te avisaremos cuando el vendedor responda.'),
        backgroundColor: AppColors.leafGreen,
      ),
    );
  } on DuplicateRequestException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.coffeeMedium),
    );
  }
}
