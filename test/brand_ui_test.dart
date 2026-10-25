import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/screens/auth/login_screen.dart';
import 'package:lotea_cafe/screens/auth/register_screen.dart';
import 'package:lotea_cafe/theme/app_theme.dart';
import 'package:lotea_cafe/widgets/brand_header.dart';

// Pruebas de la fase de refinamiento visual. No usan Firebase: LoginScreen y
// RegisterScreen solo leen SessionProvider al pulsar sus botones, que aquí no
// se pulsan.
void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void pantalla(WidgetTester tester, {double ancho = 360, double alto = 720}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(ancho, alto);
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(theme: AppTheme.light(), home: home);

  testWidgets('LoteaBrandHeader muestra nombre y eslogan, y el eslogan es opcional', (tester) async {
    pantalla(tester);
    await tester.pumpWidget(app(const Scaffold(body: LoteaBrandHeader())));
    expect(find.text('Lotea Café'), findsOneWidget);
    expect(find.text('Descubre. Compara. Conecta.'), findsOneWidget);

    await tester.pumpWidget(app(const Scaffold(body: LoteaBrandHeader(showTagline: false))));
    expect(find.text('Descubre. Compara. Conecta.'), findsNothing);
  });

  testWidgets('LoteaBrandHeader no desborda en un ancho muy pequeño', (tester) async {
    pantalla(tester, ancho: 200, alto: 400);
    await tester.pumpWidget(app(const Scaffold(body: LoteaBrandHeader(symbolHeight: 90, nameSize: 44))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('las tarjetas de rol miden lo mismo con cualquier selección', (tester) async {
    pantalla(tester, ancho: 320, alto: 640);
    await tester.pumpWidget(app(const RegisterScreen()));

    final vender = find.byKey(const ValueKey('rol_card_vendedor'));
    final comprar = find.byKey(const ValueKey('rol_card_comprador'));
    expect(tester.getSize(vender), tester.getSize(comprar));
    final tamanoInicial = tester.getSize(vender);

    await tester.tap(vender);
    await tester.pumpAndSettle();
    expect(tester.getSize(vender), tester.getSize(comprar));
    expect(tester.getSize(vender), tamanoInicial);

    await tester.tap(comprar);
    await tester.pumpAndSettle();
    expect(tester.getSize(vender), tester.getSize(comprar));
    expect(tester.getSize(comprar), tamanoInicial);
    expect(tester.getTopLeft(vender).dy, tester.getTopLeft(comprar).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el campo de nombre cambia con el rol y conserva lo escrito', (tester) async {
    pantalla(tester);
    await tester.pumpWidget(app(const RegisterScreen()));

    // Rol inicial: comprador.
    expect(find.text('Nombre completo'), findsWidgets);
    expect(find.text('Ej. María Rodríguez'), findsWidgets);
    expect(find.text('Nombre del productor o finca/marca'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo'), 'Finca La Aurora');

    await tester.tap(find.byKey(const ValueKey('rol_card_vendedor')));
    await tester.pumpAndSettle();
    expect(find.text('Nombre del productor o finca/marca'), findsWidgets);
    expect(find.text('Puedes usar tu nombre, el de tu finca o tu marca comercial.'), findsOneWidget);
    expect(find.text('Nombre completo'), findsNothing);
    expect(find.text('Finca La Aurora'), findsOneWidget); // el texto escrito se conserva

    await tester.tap(find.byKey(const ValueKey('rol_card_comprador')));
    await tester.pumpAndSettle();
    expect(find.text('Nombre completo'), findsWidgets);
    expect(find.text('Puedes usar tu nombre, el de tu finca o tu marca comercial.'), findsNothing);
    expect(find.text('Finca La Aurora'), findsOneWidget);
  });

  // Las pruebas usan la fuente Ahem (cada letra mide el tamaño de fuente), que es
  // más ancha que Roboto: si algo cabe aquí, cabe en un teléfono real. No se
  // modifica ninguna restricción de la app para que la prueba pase.
  final campoTipo = find.byType(DropdownButtonFormField<TipoComprador>);

  Future<void> mostrarCampoTipo(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  ).first;

  await tester.scrollUntilVisible(
    campoTipo,
    200,
    scrollable: scrollable,
  );

  await tester.pumpAndSettle();
  }

  for (final ancho in [280.0, 320.0, 360.0, 411.0]) {
    testWidgets('el registro no desborda con ancho $ancho (comprador y vendedor)', (tester) async {
      pantalla(tester, ancho: ancho, alto: 700);
      await tester.pumpWidget(app(const RegisterScreen()));
      expect(tester.takeException(), isNull);
      expect(campoTipo, findsOneWidget);
      await mostrarCampoTipo(tester);
      expect(tester.takeException(), isNull);
      // El selector usa todo el ancho útil del formulario (sin 28 px de margen por lado).
      expect(tester.getSize(campoTipo).width, ancho - 56);

      await tester.tap(find.byKey(const ValueKey('rol_card_vendedor')));
      await tester.pumpAndSettle();
      expect(campoTipo, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('el registro no desborda con texto del sistema ampliado', (tester) async {
    pantalla(tester, ancho: 360, alto: 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(const RegisterScreen()));
    await mostrarCampoTipo(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el tipo de comprador se puede abrir, elegir y leer en pantalla estrecha', (tester) async {
    pantalla(tester, ancho: 320, alto: 700);
    await tester.pumpWidget(app(const RegisterScreen()));
    await mostrarCampoTipo(tester);

    await tester.tap(campoTipo);
    await tester.pumpAndSettle();
    for (final tipo in TipoComprador.values) {
      expect(find.text(tipo.label), findsWidgets); // todas las opciones están en el menú
    }
    await tester.tap(find.text(TipoComprador.tostador.label).last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: campoTipo, matching: find.text('Tostador')), findsOneWidget);

    // La opción más larga queda dentro del campo (recortada si hiciera falta).
    await tester.tap(campoTipo);
    await tester.pumpAndSettle();
    await tester.tap(find.text(TipoComprador.independiente.label).last);
    await tester.pumpAndSettle();
    final seleccionado = find.descendant(of: campoTipo, matching: find.text('Comprador independiente'));
    expect(seleccionado, findsOneWidget);
    expect(tester.getRect(seleccionado).right, lessThanOrEqualTo(tester.getRect(campoTipo).right));
    expect(tester.getSize(seleccionado).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('el login no desborda en pantalla pequeña ni con el teclado abierto', (tester) async {
    pantalla(tester, ancho: 320, alto: 568);
    await tester.pumpWidget(app(const LoginScreen()));
    expect(tester.takeException(), isNull);
    expect(find.text('Iniciar sesión'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });
}
