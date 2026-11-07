import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_image.dart';
import 'unread_badge.dart';

/// Fila de una conexión comercial (compradores y vendedores). Funciona como
/// una lista de conversaciones: tocar la fila abre el chat, y el botón de chat
/// circular lo hace evidente. Debajo, indicadores de lo que está pendiente
/// ([estados]) y, a la derecha, una acción secundaria opcional (p. ej. «Cotizar»).
class ConnectionTile extends StatelessWidget {
  final String? foto;
  final String titulo;
  final String subtitulo;
  final String? meta;
  final bool noLeido;
  final List<Widget> estados;
  final Widget? accionSecundaria;
  final VoidCallback onAbrirChat;

  const ConnectionTile({
    super.key,
    required this.foto,
    required this.titulo,
    required this.subtitulo,
    required this.onAbrirChat,
    this.meta,
    this.noLeido = false,
    this.estados = const [],
    this.accionSecundaria,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAbrirChat,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppImage(path: foto, width: 56, height: 56, borderRadius: BorderRadius.circular(AppRadius.card - 2), ampliable: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
                        Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                        if (meta != null) Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Abrir chat con $titulo',
                    child: IndicadorNoLeido(
                      visible: noLeido,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(color: AppColors.coffeeMedium, shape: BoxShape.circle),
                        child: const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              if (estados.isNotEmpty || accionSecundaria != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: estados)),
                      if (accionSecundaria != null) accionSecundaria!,
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
