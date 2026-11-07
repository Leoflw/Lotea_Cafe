import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/widgets/text_prompt_dialog.dart';

/// Regresión del rechazo de cotizaciones: el controlador del diálogo no puede
/// usarse después de eliminarse ni liberarse antes de que termine la
/// animación de cierre. Cualquier excepción del framework durante el cierre
/// queda en tester.takeException() y hace fallar la prueba.
void main() {
  Future<void> abrir(WidgetTester tester, void Function(String?) alTerminar, {bool obligatorio = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await mostrarDialogoTexto(
                    context,
                    titulo: 'Rechazar solicitud',
                    etiqueta: 'Motivo (opcional)',
                    maxLength: 500,
                    obligatorio: obligatorio,
                  );
                  alTerminar(r);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('enviar con mensaje devuelve el texto recortado y cierra sin errores', (tester) async {
    String? resultado = 'sin respuesta';
    await abrir(tester, (r) => resultado = r);

    await tester.enterText(find.byType(TextField), '  No tengo disponibilidad  ');
    await tester.pump();
    await tester.tap(find.text('Enviar'));
    // Cada fotograma de la animación de cierre se reconstruye con el campo aún montado.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    expect(resultado, 'No tengo disponibilidad');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enviar sin mensaje (motivo opcional) devuelve cadena vacía', (tester) async {
    String? resultado = 'sin respuesta';
    await abrir(tester, (r) => resultado = r);

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(resultado, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar devuelve null y puede reabrirse sin errores', (tester) async {
    String? resultado = 'sin respuesta';
    await abrir(tester, (r) => resultado = r);

    await tester.enterText(find.byType(TextField), 'texto a medias');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(resultado, isNull);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    // El diálogo reabierto empieza vacío: no conserva el controlador anterior.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('con texto obligatorio, Enviar se habilita solo cuando hay contenido', (tester) async {
    await abrir(tester, (_) {}, obligatorio: true);

    ElevatedButton boton() => tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Enviar'));
    expect(boton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(boton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Ajustar el precio');
    await tester.pump();
    expect(boton().onPressed, isNotNull);
  });
}
