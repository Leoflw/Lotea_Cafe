import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote_request.dart';
import '../../repositories/quote_repository.dart';
import '../../repositories/repo_exception.dart';
import '../../state/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/remote_view.dart';
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

  @override
  Widget build(BuildContext context) {
    final q = widget.cotizacion;
    final uid = context.read<SessionProvider>().usuario?.uid;
    final repo = context.read<QuoteRepository>();
    final esComprador = uid == q.compradorId;
    final esVendedor = uid == q.sellerId;
    final efectivo = q.estadoEfectivo();
    final o = q.oferta;

    final acciones = <Widget>[];
    if (esVendedor && QuoteStateMachine.requiereRespuestaDelVendedor(q.estado)) {
      acciones.addAll([
        ElevatedButton(
          onPressed: _ocupado
              ? null
              : () async {
                  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OfferFormScreen(cotizacion: q)));
                  // `context` aquí es el de build(), no el del State: se comprueba context.mounted
                  // (el `mounted` del State no protege este contexto: lint use_build_context_synchronously).
                  if (ok == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oferta enviada'), backgroundColor: AppColors.leafGreen));
                  }
                },
          child: Text(q.oferta == null ? 'Enviar oferta' : 'Enviar nueva oferta'),
        ),
        OutlinedButton(
          onPressed: _ocupado
              ? null
              : () async {
                  final motivo = await _pedirTexto('Rechazar solicitud', 'Motivo (opcional)');
                  if (motivo == null || !mounted) return;
                  await _ejecutar(() => repo.rechazarSolicitud(quoteId: q.id, vendedorUid: uid!, motivo: motivo), 'Solicitud rechazada');
                },
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Rechazar solicitud'),
        ),
      ]);
    }
    if (esComprador && q.estado == EstadoCotizacion.ofertaEnviada) {
      if (efectivo == EstadoCotizacion.ofertaEnviada) {
        acciones.add(ElevatedButton(
          onPressed: _ocupado
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
          child: const Text('Aceptar oferta'),
        ));
      }
      acciones.addAll([
        OutlinedButton(
          onPressed: _ocupado
              ? null
              : () async {
                  final c = await _pedirTexto('Solicitar ajuste', '¿Qué quieres ajustar?', obligatorio: true);
                  if (c == null || !mounted) return;
                  await _ejecutar(() => repo.solicitarRevision(quoteId: q.id, compradorUid: uid!, comentario: c), 'Ajuste solicitado');
                },
          child: const Text('Solicitar ajuste'),
        ),
        if (efectivo == EstadoCotizacion.ofertaEnviada)
          OutlinedButton(
            onPressed: _ocupado
                ? null
                : () async {
                    final motivo = await _pedirTexto('Rechazar oferta', 'Motivo (opcional)');
                    if (motivo == null || !mounted) return;
                    await _ejecutar(() => repo.rechazarOferta(quoteId: q.id, compradorUid: uid!, motivo: motivo), 'Oferta rechazada');
                  },
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Rechazar oferta'),
          ),
      ]);
    }
    if (esComprador && QuoteStateMachine.puede(q.estado, EstadoCotizacion.cancelada, ActorCotizacion.comprador)) {
      acciones.add(TextButton(
        onPressed: _ocupado
            ? null
            : () async {
                final ok = await _confirmar('Cancelar cotización', '¿Seguro que quieres cancelar esta cotización?', 'Sí, cancelar');
                if (ok && mounted) await _ejecutar(() => repo.cancelar(quoteId: q.id, compradorUid: uid!), 'Cotización cancelada');
              },
        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        child: const Text('Cancelar cotización'),
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(child: Text(q.loteNombre, style: Theme.of(context).textTheme.titleLarge)),
            QuoteStatusChip(estado: efectivo, corto: false),
          ],
        ),
        Text(esComprador ? q.sellerNombre : q.compradorNombre, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 14),
        _Bloque(titulo: 'Solicitud', filas: [
          ('Cantidad', cantidadTexto(q.cantidad, q.unidad)),
          if ((q.lugarEntrega ?? '').isNotEmpty) ('Entrega en', q.lugarEntrega!),
          if ((q.comentario ?? '').isNotEmpty) ('Comentario', q.comentario!),
          ('Fecha', formatFechaHora(q.fecha)),
        ]),
        if (o != null) ...[
          const SizedBox(height: 12),
          _Bloque(titulo: 'Oferta (versión ${o.version})', filas: [
            ('Precio unitario', formatCOPPorUnidad(o.precioUnitarioCOP, o.unidadPrecio)),
            ('Subtotal', formatCOP(o.subtotalCOP)),
            ('Envío', formatCOP(o.envioCOP)),
            ('Total', formatCOP(o.totalCOP)),
            ('Entrega', o.tiempoEntrega),
            if (o.vigenciaHasta != null) ('Válida hasta', formatFecha(o.vigenciaHasta!)),
            if (o.condiciones.isNotEmpty) ('Condiciones', o.condiciones),
            if ((o.mensaje ?? '').isNotEmpty) ('Mensaje', o.mensaje!),
          ], destacarUltima: false),
        ],
        if (q.estado == EstadoCotizacion.revisionSolicitada && (q.revisionComentario ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _Aviso(texto: 'Ajuste solicitado: ${q.revisionComentario}'),
        ],
        if (q.estado == EstadoCotizacion.ofertaAceptada) ...[
          const SizedBox(height: 12),
          const _Aviso(
            texto: 'Acuerdo registrado. Lotea Café aún no procesa pagos, pedidos ni envíos: coordinen esos pasos directamente por el chat.',
            verde: true,
          ),
        ],
        if (efectivo == EstadoCotizacion.ofertaVencida) ...[
          const SizedBox(height: 12),
          const _Aviso(texto: 'La vigencia de esta oferta terminó. El comprador puede pedir un ajuste y el vendedor enviar una nueva.'),
        ],
        const SizedBox(height: 16),
        ...acciones.expand((w) => [w, const SizedBox(height: 8)]),
        OutlinedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Abrir chat'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(interestRequestId: q.interestRequestId, otroNombre: esComprador ? q.sellerNombre : q.compradorNombre),
          )),
        ),
        const SizedBox(height: 22),
        Text('Historial', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        StreamView<List<QuoteEvent>>(
          crear: () => repo.observarEventos(q.id),
          builder: (context, eventos) => Column(
            children: [
              for (final e in eventos)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(e.actor == ActorCotizacion.vendedor ? Icons.storefront_outlined : Icons.person_outline, size: 20),
                  title: Text(e.tipo.label + (e.versionOferta != null ? ' (v${e.versionOferta})' : '')),
                  subtitle: Text([
                    formatFechaHora(e.fecha),
                    if (e.totalCOP != null) 'Total ${formatCOP(e.totalCOP!)}',
                    if ((e.nota ?? '').isNotEmpty) e.nota!,
                  ].join('\n')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bloque extends StatelessWidget {
  final String titulo;
  final List<(String, String)> filas;
  final bool destacarUltima;
  const _Bloque({required this.titulo, required this.filas, this.destacarUltima = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final f in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 108, child: Text(f.$1, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
                    Expanded(child: Text(f.$2, style: TextStyle(fontSize: 13.5, fontWeight: f.$1 == 'Total' ? FontWeight.bold : FontWeight.normal))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final bool verde;
  const _Aviso({required this.texto, this.verde = false});

  @override
  Widget build(BuildContext context) {
    final c = verde ? AppColors.leafGreen : AppColors.coffeeMedium;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(texto, style: const TextStyle(fontSize: 13, height: 1.4)),
    );
  }
}
