import 'package:flutter/material.dart';

/// Pide un texto corto en un cuadro de diálogo (motivo de rechazo, comentario
/// de ajuste, etc.). Devuelve el texto recortado, o `null` si se cancela.
///
/// El [TextEditingController] vive dentro del State del diálogo, así que se
/// libera exactamente una vez y solo cuando Flutter desmonta el diálogo, es
/// decir, después de que termina su animación de cierre. Liberarlo desde quien
/// llama, justo después del `await showDialog`, es incorrecto: en ese momento
/// la ruta aún está animando su salida con el TextField montado (y el teclado
/// al ocultarse provoca reconstrucciones), así que el campo seguiría usando un
/// controlador ya eliminado.
Future<String?> mostrarDialogoTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required int maxLength,
  bool obligatorio = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogoTexto(
      titulo: titulo,
      etiqueta: etiqueta,
      maxLength: maxLength,
      obligatorio: obligatorio,
    ),
  );
}

class _DialogoTexto extends StatefulWidget {
  final String titulo;
  final String etiqueta;
  final int maxLength;
  final bool obligatorio;

  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    required this.maxLength,
    required this.obligatorio,
  });

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.etiqueta),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        // Se reconstruye solo el botón cuando cambia el texto.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (context, valor, _) {
            final texto = valor.text.trim();
            return ElevatedButton(
              onPressed: widget.obligatorio && texto.isEmpty ? null : () => Navigator.pop(context, texto),
              child: const Text('Enviar'),
            );
          },
        ),
      ],
    );
  }
}
