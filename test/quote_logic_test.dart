import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/quote_request.dart';

void main() {
  group('QuoteStateMachine', () {
    test('el vendedor puede ofertar o rechazar una solicitud pendiente', () {
      final destinos = QuoteStateMachine.destinos(EstadoCotizacion.solicitudPendiente, ActorCotizacion.vendedor);
      expect(destinos, {EstadoCotizacion.ofertaEnviada, EstadoCotizacion.solicitudRechazada});
    });

    test('el comprador no puede aceptar una solicitud sin oferta', () {
      expect(
        QuoteStateMachine.puede(EstadoCotizacion.solicitudPendiente, EstadoCotizacion.ofertaAceptada, ActorCotizacion.comprador),
        isFalse,
      );
    });

    test('el vendedor no puede aceptar su propia oferta', () {
      expect(
        QuoteStateMachine.puede(EstadoCotizacion.ofertaEnviada, EstadoCotizacion.ofertaAceptada, ActorCotizacion.vendedor),
        isFalse,
      );
    });

    test('el comprador puede aceptar, rechazar, pedir ajuste o cancelar una oferta', () {
      final d = QuoteStateMachine.destinos(EstadoCotizacion.ofertaEnviada, ActorCotizacion.comprador);
      expect(d, {
        EstadoCotizacion.ofertaAceptada,
        EstadoCotizacion.ofertaRechazada,
        EstadoCotizacion.revisionSolicitada,
        EstadoCotizacion.cancelada,
      });
    });

    test('tras una revisión solicitada el vendedor puede reenviar', () {
      expect(
        QuoteStateMachine.puede(EstadoCotizacion.revisionSolicitada, EstadoCotizacion.ofertaEnviada, ActorCotizacion.vendedor),
        isTrue,
      );
    });

    test('los estados finales no tienen salidas', () {
      for (final e in [
        EstadoCotizacion.ofertaAceptada,
        EstadoCotizacion.ofertaRechazada,
        EstadoCotizacion.solicitudRechazada,
        EstadoCotizacion.cancelada,
      ]) {
        expect(QuoteStateMachine.esTerminal(e), isTrue, reason: e.name);
        for (final actor in ActorCotizacion.values) {
          expect(QuoteStateMachine.destinos(e, actor), isEmpty, reason: '${e.name}/${actor.name}');
        }
      }
    });
  });

  group('QuoteCalculator', () {
    test('calcula subtotal y total en pesos enteros', () {
      final t = QuoteCalculator.calcular(cantidad: 2.5, precioUnitarioCOP: 38000, envioCOP: 12000);
      expect(t.subtotalCOP, 95000);
      expect(t.totalCOP, 107000);
    });

    test('redondea al peso más cercano', () {
      final t = QuoteCalculator.calcular(cantidad: 1.5, precioUnitarioCOP: 333);
      expect(t.subtotalCOP, 500); // 499.5 → 500
      expect(t.totalCOP, 500);
    });
  });

  group('QuoteValidator', () {
    test('rechaza cantidades no válidas', () {
      expect(QuoteValidator.solicitud(cantidad: 0, unidad: 'kg'), isNotNull);
      expect(QuoteValidator.solicitud(cantidad: null, unidad: 'kg'), isNotNull);
      expect(QuoteValidator.solicitud(cantidad: 5, unidad: 'tonelada'), isNotNull);
      expect(QuoteValidator.solicitud(cantidad: 5, unidad: 'kg'), isNull);
    });

    test('valida la oferta', () {
      expect(QuoteValidator.oferta(precioUnitarioCOP: 0, envioCOP: 0, tiempoEntrega: '3 días'), isNotNull);
      expect(QuoteValidator.oferta(precioUnitarioCOP: 1000, envioCOP: -1, tiempoEntrega: '3 días'), isNotNull);
      expect(QuoteValidator.oferta(precioUnitarioCOP: 1000, envioCOP: 0, tiempoEntrega: '  '), isNotNull);
      expect(QuoteValidator.oferta(precioUnitarioCOP: 1000, envioCOP: 0, tiempoEntrega: '3 días'), isNull);
    });

    test('la vigencia debe ser futura', () {
      final ahora = DateTime(2026, 10, 20);
      expect(
        QuoteValidator.oferta(
          precioUnitarioCOP: 1000,
          envioCOP: 0,
          tiempoEntrega: '3 días',
          vigenciaHasta: DateTime(2026, 10, 19),
          ahora: ahora,
        ),
        isNotNull,
      );
    });
  });

  group('QuoteRequest', () {
    QuoteRequest cotizacion({EstadoCotizacion estado = EstadoCotizacion.ofertaEnviada, DateTime? vigencia}) {
      return QuoteRequest(
        id: 'q1',
        interestRequestId: 'c_l',
        compradorId: 'c',
        sellerId: 's',
        coffeeLotId: 'l',
        cantidad: 10,
        unidad: 'kg',
        estado: estado,
        oferta: QuoteOffer(
          precioUnitarioCOP: 1000,
          unidadPrecio: 'kg',
          subtotalCOP: 10000,
          envioCOP: 0,
          totalCOP: 10000,
          tiempoEntrega: '3 días',
          vigenciaHasta: vigencia,
        ),
      );
    }

    test('una oferta con vigencia pasada se muestra como vencida', () {
      final q = cotizacion(vigencia: DateTime(2026, 1, 1));
      expect(q.estadoEfectivo(DateTime(2026, 6, 1)), EstadoCotizacion.ofertaVencida);
    });

    test('una oferta vigente conserva su estado', () {
      final q = cotizacion(vigencia: DateTime(2027, 1, 1));
      expect(q.estadoEfectivo(DateTime(2026, 6, 1)), EstadoCotizacion.ofertaEnviada);
    });

    test('un estado final no se convierte en vencido', () {
      final q = cotizacion(estado: EstadoCotizacion.ofertaAceptada, vigencia: DateTime(2026, 1, 1));
      expect(q.estadoEfectivo(DateTime(2026, 6, 1)), EstadoCotizacion.ofertaAceptada);
    });

    test('fromMap lee la oferta y los estados', () {
      final q = QuoteRequest.fromMap('q1', {
        'interestRequestId': 'c_l',
        'compradorId': 'c',
        'sellerId': 's',
        'coffeeLotId': 'l',
        'cantidad': 4,
        'unidad': 'kg',
        'estado': 'ofertaEnviada',
        'oferta': {
          'precioUnitarioCOP': 2000,
          'unidadPrecio': 'kg',
          'subtotalCOP': 8000,
          'envioCOP': 500,
          'totalCOP': 8500,
          'tiempoEntrega': '5 días',
          'version': 2,
        },
      });
      expect(q.estado, EstadoCotizacion.ofertaEnviada);
      expect(q.oferta!.totalCOP, 8500);
      expect(q.oferta!.version, 2);
    });
  });
}
