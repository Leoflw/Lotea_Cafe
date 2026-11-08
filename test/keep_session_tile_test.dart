import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/services/session_preference.dart';
import 'package:lotea_cafe/widgets/keep_session_tile.dart';
import 'package:provider/provider.dart';

class _Almacen implements AlmacenPreferenciaSesion {
  bool? valor;
  bool falla = false;
  @override
  Future<bool?> leer() async => valor;
  @override
  Future<void> guardar(bool mantener) async {
    if (falla) throw StateError('no se pudo guardar');
    valor = mantener;
  }
}

Widget _app(PreferenciaSesion p) => ChangeNotifierProvider<PreferenciaSesion>.value(
      value: p,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: KeepSessionTile()))),
    );

bool _activo(WidgetTester t) => t.widget<SwitchListTile>(find.byType(SwitchListTile)).value;

void main() {
  testWidgets('aparece activado por defecto', (tester) async {
    final p = await PreferenciaSesion.cargar(_Almacen());
    await tester.pumpWidget(_app(p));
    expect(find.text('Mantener sesión iniciada'), findsOneWidget);
    expect(_activo(tester), isTrue);
  });

  testWidgets('al desactivarlo se guarda la preferencia y cambia el texto', (tester) async {
    final a = _Almacen();
    final p = await PreferenciaSesion.cargar(a);
    await tester.pumpWidget(_app(p));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(_activo(tester), isFalse);
    expect(a.valor, isFalse);
    expect(p.mantener, isFalse);
    expect(find.textContaining('tendrás que iniciar sesión'), findsOneWidget);
  });

  testWidgets('si no se puede guardar, vuelve al valor anterior y avisa', (tester) async {
    final a = _Almacen()..falla = true;
    final p = await PreferenciaSesion.cargar(a);
    await tester.pumpWidget(_app(p));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(_activo(tester), isTrue);
    expect(find.text('No se pudo guardar el cambio. Inténtalo de nuevo.'), findsOneWidget);
  });
}
