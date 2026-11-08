import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/services/session_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Almacen implements AlmacenPreferenciaSesion {
  bool? valor;
  bool fallaLeer = false;
  bool fallaGuardar = false;
  int escrituras = 0;
  _Almacen([this.valor]);

  @override
  Future<bool?> leer() async {
    if (fallaLeer) throw StateError('no se pudo leer');
    return valor;
  }

  @override
  Future<void> guardar(bool mantener) async {
    if (fallaGuardar) throw StateError('no se pudo guardar');
    escrituras++;
    valor = mantener;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferenciaSesion', () {
    test('sin valor guardado, la sesión se mantiene (activada por defecto)', () async {
      final p = await PreferenciaSesion.cargar(_Almacen());
      expect(p.mantener, isTrue);
    });

    test('lee el valor guardado', () async {
      expect((await PreferenciaSesion.cargar(_Almacen(false))).mantener, isFalse);
      expect((await PreferenciaSesion.cargar(_Almacen(true))).mantener, isTrue);
    });

    test('si la lectura falla, se mantiene la sesión (nunca se cierra por un fallo del almacenamiento)', () async {
      final a = _Almacen(false)..fallaLeer = true;
      expect((await PreferenciaSesion.cargar(a)).mantener, isTrue);
    });

    test('cambiar guarda, notifica y devuelve true', () async {
      final a = _Almacen();
      final p = await PreferenciaSesion.cargar(a);
      var avisos = 0;
      p.addListener(() => avisos++);
      expect(await p.cambiar(false), isTrue);
      expect(p.mantener, isFalse);
      expect(a.valor, isFalse);
      expect(avisos, 1);
    });

    test('cambiar al mismo valor no escribe', () async {
      final a = _Almacen();
      final p = await PreferenciaSesion.cargar(a);
      expect(await p.cambiar(true), isTrue);
      expect(a.escrituras, 0);
    });

    test('si guardar falla, devuelve false y conserva el valor anterior', () async {
      final a = _Almacen()..fallaGuardar = true;
      final p = await PreferenciaSesion.cargar(a);
      expect(await p.cambiar(false), isFalse);
      expect(p.mantener, isTrue);
    });

    test('en memoria funciona sin almacenamiento', () async {
      final p = PreferenciaSesion.enMemoria();
      expect(p.mantener, isTrue);
      expect(await p.cambiar(false), isTrue);
      expect(p.mantener, isFalse);
    });
  });

  group('AlmacenPreferenciaSesionLocal (shared_preferences simulado)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda SOLO el booleano mantener_sesion', () async {
      final almacen = AlmacenPreferenciaSesionLocal();
      expect(await almacen.leer(), isNull);
      await almacen.guardar(false);
      expect(await almacen.leer(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'mantener_sesion'});
    });
  });
}
