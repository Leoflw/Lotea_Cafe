import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/services/device_token_service.dart';
import 'package:lotea_cafe/services/push_gateway.dart';
import 'package:lotea_cafe/widgets/push_activation_card.dart';
import 'package:provider/provider.dart';

class _Gateway implements PushGateway {
  PushPermiso permiso;
  PushPermiso trasPedir;
  int pedidos = 0;
  _Gateway({this.permiso = PushPermiso.noDeterminado, this.trasPedir = PushPermiso.concedido});

  @override
  Future<PushPermiso> estadoPermiso() async => permiso;
  @override
  Future<PushPermiso> pedirPermiso() async {
    pedidos++;
    permiso = trasPedir;
    return permiso;
  }

  @override
  Future<String?> obtenerToken() async => 'token-de-prueba-con-longitud-suficiente';
  @override
  Future<void> eliminarToken() async {}
  @override
  Stream<String> get tokenRenovado => Stream<String>.empty();
  @override
  Stream<PushMensaje> get enPrimerPlano => Stream<PushMensaje>.empty();
  @override
  Stream<PushMensaje> get alAbrirNotificacion => Stream<PushMensaje>.empty();
  @override
  Future<PushMensaje?> get mensajeInicial async => null;
}

class _Almacen implements DeviceTokenStore {
  final guardados = <String>[];
  @override
  Future<void> guardar({required String uid, required String tokenId, required String token, required String plataforma}) async =>
      guardados.add('$uid/$tokenId');
  @override
  Future<void> eliminar({required String uid, required String tokenId}) async {}
}

Future<DeviceTokenService> _montar(WidgetTester tester, _Gateway g, _Almacen a, {bool conSesion = true}) async {
  final servicio = DeviceTokenService(gateway: g, store: a);
  if (conSesion) await tester.runAsync(() => servicio.alCambiarUsuario('ana'));
  await tester.pumpWidget(
    ChangeNotifierProvider<DeviceTokenService>.value(
      value: servicio,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PushActivationCard()))),
    ),
  );
  return servicio;
}

void main() {
  testWidgets('explica para qué sirven y NO muestra el diálogo del sistema por sí sola', (tester) async {
    final g = _Gateway();
    await _montar(tester, g, _Almacen());
    expect(find.text('Notificaciones'), findsOneWidget);
    expect(find.textContaining('mensajes y novedades de cotizaciones'), findsOneWidget);
    expect(find.text('Activar notificaciones'), findsOneWidget);
    expect(g.pedidos, 0);
  });

  testWidgets('al pulsar «Activar» pide el permiso UNA vez, registra el dispositivo y confirma', (tester) async {
    final g = _Gateway();
    final a = _Almacen();
    await _montar(tester, g, a);
    await tester.tap(find.text('Activar notificaciones'));
    await tester.pump();
    await tester.pump();
    expect(g.pedidos, 1);
    expect(a.guardados, hasLength(1));
    expect(find.textContaining('Activadas en este dispositivo'), findsOneWidget);
    expect(find.text('Activar notificaciones'), findsNothing);
  });

  testWidgets('si el usuario rechaza el permiso no hay errores: explica cómo activarlas y permite reintentar', (tester) async {
    final g = _Gateway(trasPedir: PushPermiso.denegado);
    final a = _Almacen();
    await _montar(tester, g, a);
    await tester.tap(find.text('Activar notificaciones'));
    await tester.pump();
    await tester.pump();
    expect(a.guardados, isEmpty);
    expect(find.textContaining('Ajustes → Aplicaciones → Lotea Café → Notificaciones'), findsOneWidget);
    expect(find.text('Volver a intentarlo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con el permiso ya concedido se ve activada sin tocar nada y sin diálogo', (tester) async {
    final g = _Gateway(permiso: PushPermiso.concedido);
    await _montar(tester, g, _Almacen());
    expect(find.textContaining('Activadas en este dispositivo'), findsOneWidget);
    expect(g.pedidos, 0);
  });
}
