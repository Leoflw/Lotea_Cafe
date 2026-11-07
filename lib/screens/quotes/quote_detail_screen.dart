import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote_request.dart';
import '../../repositories/quote_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_image.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/text_prompt_dialog.dart';
import '../chat/chat_screen.dart';
import 'offer_form_screen.dart';
import 'quote_widgets.dart';

/// Detalle de una cotización, para comprador y vendedor. Las acciones
/// disponibles salen de [QuoteStateMachine] según quién mira y en qué
/// estado está.
class QuoteDetailScreen extends StatelessWidget {
  final String quoteId;
  const QuoteDetailScreen({super.key, required this.quoteId});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<QuoteRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cotización')),
      body: StreamView<QuoteRequest?>(
        crear: () => repo.observar(quoteId),
        builder: (context, q) {
          if (q == null) {
            return const EmptyState(icono: Icons.request_quote_outlined, titulo: 'Esta cotización ya no existe');
          }
          return _Contenido(cotizacion: q);
        },
      ),
    );
  }
}

class _Contenido extends StatefulWidget {
  final QuoteRequest cotizacion;
  const _Contenido({required this.cotizacion});

  @override
  State<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends State<_Contenido> {
  bool _ocupado = false;

  Future<void> _ejecutar(Future<void> Function() accion, String exito) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(exito), backgroundColor: AppColors.leafGreen));
      }
    } on RepoException catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String boton) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(boton)),
        ],
      ),
    );
    return r ?? false;
  }

  Future<String?> _pedirTexto(String titulo, String etiqueta, {bool obligatorio = false}) {
    return mostrarDialogoTexto(
      context,
      titulo: titulo,
      etiqueta: etiqueta,
      maxLength: QuoteLimits.maxComentario,
      obligatorio: obligatorio,
    );
  }

  /// Qué toca hacer ahora y a quién, según el estado vigente y quién mira.
  /// Solo describe; las acciones disponibles salen de [QuoteStateMachine].
  String _proximaAccion(EstadoCotizacion e, {required bool esComprador, required bool esVendedor}) {
    if (esVendedor) {
      switch (e) {
        case EstadoCotizacion.solicitudPendiente:
          return 'Te toca responder: envía una oferta o rechaza la solicitud.';
        case EstadoCotizacion.revisionSolicitada:
          return 'El comprador pidió un ajuste. Envía una nueva oferta o rechaza la solicitud.';
        case EstadoCotizacion.ofertaEnviada:
          return 'Esperando la respuesta del comprador.';
        case EstadoCotizacion.ofertaVencida:
          return 'La vigencia de tu oferta terminó. El comprador puede pedir un ajuste y tú enviar una nueva.';
        case EstadoCotizacion.ofertaAceptada:
          return 'El comprador aceptó tu oferta. Coordinen el pago y la entrega por el chat.';
        case EstadoCotizacion.ofertaRechazada:
          return 'El comprador rechazó la oferta.';
        case EstadoCotizacion.solicitudRechazada:
          return 'Rechazaste esta solicitud.';
        case EstadoCotizacion.cancelada:
          return 'El comprador canceló esta cotización.';
      }
    }
    if (esComprador) {
      switch (e) {
        case EstadoCotizacion.solicitudPendiente:
          return 'Esperando la respuesta del vendedor.';
        case EstadoCotizacion.ofertaEnviada:
          return 'El vendedor te envió una oferta. Puedes aceptarla, pedir un ajuste o rechazarla.';
        case EstadoCotizacion.revisionSolicitada:
          return 'Pediste un ajuste. Esperando una nueva oferta del vendedor.';
        case EstadoCotizacion.ofertaVencida:
          return 'La vigencia de la oferta terminó. Puedes pedir un ajuste.';
        case EstadoCotizacion.ofertaAceptada:
          return 'Aceptaste la oferta. Coordina el pago y la entrega con el vendedor por el chat.';
        case EstadoCotizacion.ofertaRechazada:
          return 'Rechazaste esta oferta.';
        case EstadoCotizacion.solicitudRechazada:
          return 'El vendedor rechazó tu solicitud.';
        case EstadoCotizacion.cancelada:
          return 'Cancelaste esta cotización.';
      }
    }
    return e.label;
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.cotizacion;
    final uid = context.read<SessionProvider>().usuario?.uid;
    final repo = context.read<QuoteRepository>();
    final esComprador = uid == q.compradorId;
    final esVendedor = uid == q.sellerId;
    final efectivo = q.estadoEfectivo();
    final o = q.oferta;
    final textTheme = Theme.of(context).textTheme;

    // Las acciones se agrupan por peso: UNA principal, las secundarias y las
    // destructivas (discretas). Las condiciones para cada una son las mismas
    // de siempre y salen de QuoteStateMachine.
    final principal = <_AccionDef>[];
    final secundarias = <_AccionDef>[];
    final destructivas = <_AccionDef>[];
    if (esVendedor && QuoteStateMachine.requiereRespuestaDelVendedor(q.estado)) {
      principal.add(_AccionDef(
        q.oferta == null ? 'Enviar oferta' : 'Enviar nueva oferta',
        _ocupado
            ? null
            : () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OfferFormScreen(cotizacion: q)));
                // `context` aquí es el de build(), no el del State: se comprueba context.mounted
                // (el `mounted` del State no protege este contexto: lint use_build_context_synchronously).
                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oferta enviada'), backgroundColor: AppColors.leafGreen));
                }
              },
      ));
      destructivas.add(_AccionDef(
        'Rechazar solicitud',
        _ocupado
            ? null
            : () async {
                final motivo = await _pedirTexto('Rechazar solicitud', 'Motivo (opcional)');
                if (motivo == null || !mounted) return;
                await _ejecutar(() => repo.rechazarSolicitud(quoteId: q.id, vendedorUid: uid!, motivo: motivo), 'Solicitud rechazada');
              },
      ));
    }
    if (esComprador && q.estado == EstadoCotizacion.ofertaEnviada) {
      if (efectivo == EstadoCotizacion.ofertaEnviada) {
        principal.add(_AccionDef(
          'Aceptar oferta',
          _ocupado
              ? null
              : () async {
                  final ok = await _confirmar(
                    'Aceptar oferta',
                    'Aceptarás ${formatCOP(o!.totalCOP)} por ${cantidadTexto(q.cantidad, q.unidad)}. '
                        'Esto solo registra el acuerdo: Lotea Café no genera pedido ni cobra. El pago y la entrega los coordinan directamente comprador y vendedor.',
                    'Aceptar oferta',
                  );
                  if (ok && mounted) await _ejecutar(() => repo.aceptarOferta(quoteId: q.id, compradorUid: uid!), 'Oferta aceptada');
                },
        ));
      }
      secundarias.add(_AccionDef(
        'Solicitar ajuste',
        _ocupado
            ? null
            : () async {
                final c = await _pedirTexto('Solicitar ajuste', '¿Qué quieres ajustar?', obligatorio: true);
                if (c == null || !mounted) return;
                await _ejecutar(() => repo.solicitarRevision(quoteId: q.id, compradorUid: uid!, comentario: c), 'Ajuste solicitado');
              },
      ));
      if (efectivo == EstadoCotizacion.ofertaEnviada) {
        destructivas.add(_AccionDef(
          'Rechazar oferta',
          _ocupado
              ? null
              : () async {
                  final motivo = await _pedirTexto('Rechazar oferta', 'Motivo (opcional)');
                  if (motivo == null || !mounted) return;
                  await _ejecutar(() => repo.rechazarOferta(quoteId: q.id, compradorUid: uid!, motivo: motivo), 'Oferta rechazada');
                },
        ));
      }
    }
    if (esComprador && QuoteStateMachine.puede(q.estado, EstadoCotizacion.cancelada, ActorCotizacion.comprador)) {
      destructivas.add(_AccionDef(
        'Cancelar cotización',
        _ocupado
            ? null
            : () async {
                final ok = await _confirmar('Cancelar cotización', '¿Seguro que quieres cancelar esta cotización?', 'Sí, cancelar');
                if (ok && mounted) await _ejecutar(() => repo.cancelar(quoteId: q.id, compradorUid: uid!), 'Cotización cancelada');
              },
      ));
    }

    // Si no hay acción principal (p. ej. oferta vencida), la primera
    // secundaria pasa a ser la protagonista para que siempre haya un camino claro.
    final promovida = principal.isEmpty && secundarias.isNotEmpty ? secundarias.first : null;
    final botonPrincipal = principal.isNotEmpty ? principal.first : promovida;
    final botonesSecundarios = secundarias.where((a) => a != promovida).toList();
    final contraparte = esComprador ? q.sellerNombre : q.compradorNombre;
    final tono = toneEstadoCotizacion(efectivo);
    final requiereAccion = botonPrincipal != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        // ---------- ENCABEZADO ----------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppImage(path: q.loteFoto, width: 64, height: 64, borderRadius: BorderRadius.circular(AppRadius.card - 2), ampliable: false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.loteNombre.isEmpty ? 'Café' : q.loteNombre, style: textTheme.headlineSmall?.copyWith(fontSize: 23, height: 1.15)),
                  const SizedBox(height: 2),
                  Text(contraparte, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(height: 8),
                  QuoteStatusChip(estado: efectivo, corto: false),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ---------- PRÓXIMA ACCIÓN ----------
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: tono.background, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(requiereAccion ? Icons.notifications_active_outlined : Icons.info_outline, size: 20, color: tono.foreground),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _proximaAccion(efectivo, esComprador: esComprador, esVendedor: esVendedor),
                      style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, color: tono.foreground),
                    ),
                  ),
                ],
              ),
              if (botonPrincipal != null) ...[
                const SizedBox(height: 14),
                ElevatedButton(onPressed: botonPrincipal.onPressed, child: Text(botonPrincipal.etiqueta)),
              ],
              for (final a in botonesSecundarios) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: a.onPressed, child: Text(a.etiqueta)),
              ],
              if (destructivas.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    for (final a in destructivas)
                      TextButton(
                        onPressed: a.onPressed,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(48, 44)),
                        child: Text(a.etiqueta),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Abrir chat'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(interestRequestId: q.interestRequestId, otroNombre: contraparte),
          )),
        ),

        // ---------- RESUMEN DE LA OFERTA ----------
        const SizedBox(height: 22),
        _ResumenPrecio(cotizacion: q),

        // ---------- AVISOS ----------
        if (q.estado == EstadoCotizacion.revisionSolicitada && (q.revisionComentario ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _Nota(icono: Icons.edit_note, tono: StatusTone.warning, titulo: 'Ajuste solicitado', texto: q.revisionComentario!),
        ],
        if (q.estado == EstadoCotizacion.ofertaAceptada) ...[
          const SizedBox(height: 12),
          const _Nota(
            icono: Icons.handshake_outlined,
            tono: StatusTone.success,
            titulo: 'Acuerdo registrado',
            texto: 'Lotea Café aún no procesa pagos, pedidos ni envíos: coordinen esos pasos directamente por el chat.',
          ),
        ],
        if (efectivo == EstadoCotizacion.ofertaVencida) ...[
          const SizedBox(height: 12),
          const _Nota(
            icono: Icons.schedule,
            tono: StatusTone.neutral,
            titulo: 'Oferta vencida',
            texto: 'La vigencia de esta oferta terminó. El comprador puede pedir un ajuste y el vendedor enviar una nueva.',
          ),
        ],

        // ---------- DETALLE COMERCIAL ----------
        const SizedBox(height: 22),
        _Documento(
          secciones: [
            _SeccionDoc('Partes', [
              ('Comprador', q.compradorNombre + (esComprador ? ' (tú)' : '')),
              ('Vendedor', q.sellerNombre + (esVendedor ? ' (tú)' : '')),
            ]),
            _SeccionDoc('Solicitud', [
              ('Cantidad', cantidadTexto(q.cantidad, q.unidad)),
              if ((q.lugarEntrega ?? '').isNotEmpty) ('Entrega en', q.lugarEntrega!),
              if ((q.comentario ?? '').isNotEmpty) ('Comentario', q.comentario!),
              ('Fecha', formatFechaHora(q.fecha)),
            ]),
            if (o != null)
              _SeccionDoc('Oferta · versión ${o.version}', [
                ('Precio unitario', formatCOPPorUnidad(o.precioUnitarioCOP, o.unidadPrecio)),
                ('Subtotal', formatCOP(o.subtotalCOP)),
                ('Envío', formatCOP(o.envioCOP)),
                ('Total', formatCOP(o.totalCOP)),
                ('Entrega', o.tiempoEntrega),
                if (o.vigenciaHasta != null) ('Válida hasta', formatFecha(o.vigenciaHasta!)),
                if (o.condiciones.isNotEmpty) ('Condiciones', o.condiciones),
                if ((o.mensaje ?? '').isNotEmpty) ('Mensaje', o.mensaje!),
              ]),
          ],
        ),

        // ---------- NEGOCIACIÓN ----------
        const SizedBox(height: 26),
        Text('Negociación', style: textTheme.headlineSmall?.copyWith(fontSize: 21)),
        const SizedBox(height: 12),
        StreamView<List<QuoteEvent>>(
          crear: () => repo.observarEventos(q.id),
          builder: (context, eventos) => _LineaTiempo(eventos: eventos),
        ),
      ],
    );
  }
}

class _AccionDef {
  final String etiqueta;
  final VoidCallback? onPressed;
  const _AccionDef(this.etiqueta, this.onPressed);
}

/// Cifra principal de la cotización: el total ofertado (si ya hay oferta) o la
/// cantidad pedida (si todavía no).
class _ResumenPrecio extends StatelessWidget {
  final QuoteRequest cotizacion;
  const _ResumenPrecio({required this.cotizacion});

  @override
  Widget build(BuildContext context) {
    final q = cotizacion;
    final o = q.oferta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardBorder, border: Border.all(color: AppColors.outline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(o == null ? 'Cantidad solicitada' : 'Total ofertado', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.inkSoft, letterSpacing: 0.3))),
              if (o != null) StatusPill(label: 'Oferta v${o.version}', tone: StatusTone.info),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            o == null ? cantidadTexto(q.cantidad, q.unidad) : formatCOP(o.totalCOP),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.coffeeDark, height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            o == null
                ? 'Aún no hay una oferta del vendedor.'
                : '${formatCOPPorUnidad(o.precioUnitarioCOP, o.unidadPrecio)} × ${cantidadTexto(q.cantidad, q.unidad)}'
                    '${o.envioCOP > 0 ? ' + envío' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (o != null && o.vigenciaHasta != null) ...[
            const SizedBox(height: 2),
            Text('Válida hasta ${formatFecha(o.vigenciaHasta!)}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _SeccionDoc {
  final String titulo;
  final List<(String, String)> filas;
  const _SeccionDoc(this.titulo, this.filas);
}

/// Detalle comercial leído como un documento: una sola superficie con
/// secciones (Partes, Solicitud, Oferta) separadas por líneas finas.
class _Documento extends StatelessWidget {
  final List<_SeccionDoc> secciones;
  const _Documento({required this.secciones});

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    for (var i = 0; i < secciones.length; i++) {
      if (i > 0) hijos.add(const Divider(height: 1));
      final sec = secciones[i];
      hijos.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sec.titulo.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.inkSoft)),
              const SizedBox(height: 8),
              for (final f in sec.filas) _FilaDoc(etiqueta: f.$1, valor: f.$2),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardBorder, border: Border.all(color: AppColors.outline)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
    );
  }
}

class _FilaDoc extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDoc({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    final total = etiqueta == 'Total';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: total ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6) : const EdgeInsets.symmetric(vertical: 3),
      decoration: total ? BoxDecoration(color: AppColors.surfaceWarm, borderRadius: BorderRadius.circular(8)) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(etiqueta, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13))),
          Expanded(child: Text(valor, style: TextStyle(fontSize: total ? 15 : 13.5, fontWeight: total ? FontWeight.w800 : FontWeight.w600, color: AppColors.coffeeDark))),
        ],
      ),
    );
  }
}

/// Aviso con título, icono y tono del sistema semántico (reemplaza al
/// recuadro de color translúcido).
class _Nota extends StatelessWidget {
  final IconData icono;
  final StatusTone tono;
  final String titulo;
  final String texto;
  const _Nota({required this.icono, required this.tono, required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tono.background, borderRadius: BorderRadius.circular(AppRadius.control + 2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: tono.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: tono.foreground)),
                const SizedBox(height: 2),
                Text(texto, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.coffeeDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Historial de la negociación como línea de tiempo: quién hizo qué, cuándo,
/// en qué versión de la oferta y con qué total o nota.
class _LineaTiempo extends StatelessWidget {
  final List<QuoteEvent> eventos;
  const _LineaTiempo({required this.eventos});

  @override
  Widget build(BuildContext context) {
    if (eventos.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < eventos.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: eventos[i].actor == ActorCotizacion.vendedor ? AppColors.successContainer : AppColors.surfaceWarm,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          eventos[i].actor == ActorCotizacion.vendedor ? Icons.storefront_outlined : Icons.person_outline,
                          size: 17,
                          color: eventos[i].actor == ActorCotizacion.vendedor ? AppColors.leafGreen : AppColors.coffeeMedium,
                        ),
                      ),
                      if (i < eventos.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.outline)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventos[i].tipo.label + (eventos[i].versionOferta != null ? ' (v${eventos[i].versionOferta})' : ''),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.coffeeDark),
                        ),
                        Text(
                          '${eventos[i].actor == ActorCotizacion.vendedor ? 'Vendedor' : 'Comprador'} · ${formatFechaHora(eventos[i].fecha)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (eventos[i].totalCOP != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Total ${formatCOP(eventos[i].totalCOP!)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.coffeeDark)),
                          ),
                        if ((eventos[i].nota ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('«${eventos[i].nota}»', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.inkSoft, height: 1.35)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
