import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/models/seller_profile.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/utils/photo_limits.dart';

String _url(String n) => 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/$n.jpg';
List<String> _urls(int n) => List.generate(n, (i) => _url('f$i'));
List<String> _ids(int n) => List.generate(n, (i) => 'id$i');

CoffeeLot _lote(int fotos, {String nombre = 'Caturra', EstadoLote estado = EstadoLote.borrador}) => CoffeeLot(
      id: '',
      sellerId: 'u1',
      nombre: nombre,
      variedades: const ['Caturra'],
      proceso: 'Lavado',
      precioCOP: 32000,
      fotos: _urls(fotos),
      fotosStoragePaths: _ids(fotos),
      sellerNombreMarca: 'Finca La Esperanza',
      departamento: 'Huila',
      region: 'Huila',
      estado: estado,
    );

SellerProfile _perfil({required int galeria, String? principal, String marca = 'Finca La Esperanza'}) => SellerProfile(
      id: 'u1',
      usuarioId: 'u1',
      nombreMarca: marca,
      fincaPrincipal: 'La Esperanza',
      fotoPrincipal: principal,
      fotoPrincipalStoragePath: principal == null ? null : 'id-principal',
      galeria: _urls(galeria),
      galeriaStoragePaths: _ids(galeria),
      region: 'Huila',
      departamento: 'Huila',
    );

Matcher _validacion() => throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion));

void main() {
  group('valores y textos', () {
    test('límites finales', () {
      expect(PhotoLimits.maxCafe, 5);
      expect(PhotoLimits.maxGaleriaMarca, 6);
    });

    test('contadores con el formato pedido', () {
      expect(PhotoLimits.contadorCafe(3), '3 de 5 fotos');
      expect(PhotoLimits.contadorCafe(0), '0 de 5 fotos');
      expect(PhotoLimits.contadorGaleria(2), '2 de 6 fotos de galería');
    });

    test('al llegar al máximo se impide agregar y se explica cómo liberar un espacio', () {
      expect(PhotoLimits.puedeAgregar(4, PhotoLimits.maxCafe), isTrue);
      expect(PhotoLimits.puedeAgregar(5, PhotoLimits.maxCafe), isFalse);
      expect(PhotoLimits.puedeAgregar(6, PhotoLimits.maxGaleriaMarca), isFalse);
      expect(PhotoLimits.mensajeCafeLleno(), allOf(contains('5 fotos'), contains('Quita una')));
      expect(PhotoLimits.mensajeGaleriaLlena(), allOf(contains('6 fotos'), contains('Quita una')));
    });

    test('repartir: solo entran las fotos que caben, en el orden elegido', () {
      final r = PhotoLimits.repartir(3, PhotoLimits.maxCafe, ['a', 'b', 'c', 'd']);
      expect(r.aceptadas, ['a', 'b']);
      expect(r.descartadas, 2);
      final lleno = PhotoLimits.repartir(5, PhotoLimits.maxCafe, ['a']);
      expect(lleno.aceptadas, isEmpty);
      expect(lleno.descartadas, 1);
      final cabeTodo = PhotoLimits.repartir(0, PhotoLimits.maxGaleriaMarca, ['a', 'b']);
      expect(cabeTodo.aceptadas, ['a', 'b']);
      expect(cabeTodo.descartadas, 0);
    });

    test('mensaje de selección recortada', () {
      final m = PhotoLimits.mensajeSeleccionRecortada(agregadas: 2, descartadas: 1, max: 5, galeria: false);
      expect(m, allOf(contains('Se agregaron 2 fotos'), contains('otra quedó fuera'), contains('máximo es 5')));
      expect(PhotoLimits.mensajeSeleccionRecortada(agregadas: 1, descartadas: 3, max: 6, galeria: true), contains('Se agregó 1 foto'));
    });
  });

  group('validarCantidad (política con datos antiguos)', () {
    String? v(int nuevo, {int previo = 0}) => PhotoLimits.validarCantidad(nuevo: nuevo, max: 5, previo: previo, galeria: false);

    test('dentro del máximo siempre se puede', () {
      expect(v(0), isNull);
      expect(v(5), isNull);
    });
    test('por encima del máximo en un documento nuevo no se puede', () {
      expect(v(6), isNotNull);
    });
    test('un documento antiguo con 8 fotos puede conservarlas o reducirlas, no aumentarlas', () {
      expect(v(8, previo: 8), isNull);
      expect(v(7, previo: 8), isNull);
      expect(v(5, previo: 8), isNull);
      expect(v(9, previo: 8), isNotNull);
    });
    test('mensajes distintos para café y galería', () {
      expect(PhotoLimits.validarCantidad(nuevo: 7, max: 6, galeria: true), contains('galería'));
      expect(PhotoLimits.validarCantidad(nuevo: 6, max: 5, galeria: false), contains('café'));
    });
  });

  group('repositorio de cafés', () {
    late FakeFirebaseFirestore db;
    late CoffeeLotRepository repo;
    setUp(() {
      db = FakeFirebaseFirestore();
      repo = CoffeeLotRepository(db: db);
    });

    test('se guardan hasta 5 fotos', () async {
      final id = await repo.guardarLote(_lote(5));
      expect((await repo.obtener(id))!.fotos.length, 5);
    });

    test('un café nuevo con 6 fotos se rechaza y no crea ningún documento', () async {
      await expectLater(repo.guardarLote(_lote(6)), _validacion());
      expect((await db.collection('coffeeLots').get()).docs, isEmpty);
    });

    test('publicar con 6 fotos también se rechaza', () async {
      await expectLater(repo.guardarLote(_lote(6, estado: EstadoLote.publicado)), _validacion());
    });

    test('no se puede pasar de 5 a 6 fotos al editar', () async {
      final id = await repo.guardarLote(_lote(5));
      await expectLater(repo.guardarLote(_lote(6), idExistente: id), _validacion());
      expect((await repo.obtener(id))!.fotos.length, 5);
    });

    Future<void> sembrarAntiguo(int fotos) => db.collection('coffeeLots').doc('viejo').set({
          'sellerId': 'u1',
          'nombre': 'Café antiguo',
          'estado': 'borrador',
          'fotos': _urls(fotos),
          'fotosStoragePaths': _ids(fotos),
        });

    test('un café antiguo con 8 fotos permite editar otros datos manteniendo las 8', () async {
      await sembrarAntiguo(8);
      await repo.guardarLote(_lote(8, nombre: 'Nombre nuevo'), idExistente: 'viejo');
      final doc = (await db.collection('coffeeLots').doc('viejo').get()).data()!;
      expect(doc['nombre'], 'Nombre nuevo');
      expect((doc['fotos'] as List).length, 8, reason: 'no se recortan ni se borran fotos automáticamente');
    });

    test('un café antiguo se puede reducir gradualmente, pero no aumentar', () async {
      await sembrarAntiguo(8);
      await repo.guardarLote(_lote(6), idExistente: 'viejo');
      await repo.guardarLote(_lote(5), idExistente: 'viejo');
      await expectLater(repo.guardarLote(_lote(6), idExistente: 'viejo'), _validacion());
      expect((await repo.obtener('viejo'))!.fotos.length, 5);
    });

    test('un café antiguo con 8 fotos no admite una novena', () async {
      await sembrarAntiguo(8);
      await expectLater(repo.guardarLote(_lote(9), idExistente: 'viejo'), _validacion());
      expect((await repo.obtener('viejo'))!.fotos.length, 8);
    });
  });

  group('repositorio de perfil de marca', () {
    late FakeFirebaseFirestore db;
    late SellerRepository repo;
    setUp(() {
      db = FakeFirebaseFirestore();
      repo = SellerRepository(db: db);
    });

    test('6 fotos de galería más la foto principal: la principal no cuenta', () async {
      await repo.guardarPerfil(_perfil(galeria: 6, principal: _url('principal')));
      final p = (await repo.obtener('u1'))!;
      expect(p.galeria.length, 6);
      expect(p.fotoPrincipal, _url('principal'));
    });

    test('7 fotos de galería se rechazan', () async {
      await expectLater(repo.guardarPerfil(_perfil(galeria: 7)), _validacion());
      expect((await db.collection('sellerProfiles').get()).docs, isEmpty);
    });

    test('no se puede pasar de 6 a 7', () async {
      await repo.guardarPerfil(_perfil(galeria: 6));
      await expectLater(repo.guardarPerfil(_perfil(galeria: 7)), _validacion());
      expect((await repo.obtener('u1'))!.galeria.length, 6);
    });

    test('un perfil antiguo con 10 fotos se puede editar y reducir, no aumentar', () async {
      await db.collection('sellerProfiles').doc('u1').set({
        'usuarioId': 'u1',
        'nombreMarca': 'Marca',
        'fincaPrincipal': 'Finca',
        'galeria': _urls(10),
        'galeriaStoragePaths': _ids(10),
        'verificado': false,
      });
      await repo.guardarPerfil(_perfil(galeria: 10, marca: 'Marca renombrada'));
      expect((await repo.obtener('u1'))!.nombreMarca, 'Marca renombrada');
      expect((await repo.obtener('u1'))!.galeria.length, 10);
      await repo.guardarPerfil(_perfil(galeria: 7));
      await expectLater(repo.guardarPerfil(_perfil(galeria: 8)), _validacion());
      expect((await repo.obtener('u1'))!.galeria.length, 7);
    });
  });

  group('coherencia con firestore.rules', () {
    late String reglas;
    setUpAll(() => reglas = File('firestore.rules').readAsStringSync());

    test('los límites de fotos de las reglas coinciden con PhotoLimits', () {
      final cafe = PhotoLimits.maxCafe;
      final galeria = PhotoLimits.maxGaleriaMarca;
      expect(reglas, contains('incoming().fotos.size() <= $cafe'));
      expect(reglas, contains("photoCountOk(incoming().fotos.size(), resource.data.get('fotos', []).size(), $cafe)"));
      expect(reglas, contains('incoming().galeria.size() <= $galeria'));
      expect(reglas, contains("photoCountOk(incoming().galeria.size(), resource.data.get('galeria', []).size(), $galeria)"));
    });

    test('no quedan los límites anteriores (10 y 12)', () {
      expect(reglas, isNot(contains('fotos.size() <= 10')));
      expect(reglas, isNot(contains('galeria.size() <= 12')));
    });

    test('la tolerancia a datos antiguos está definida', () {
      expect(reglas, contains('function photoCountOk(newCount, oldCount, maxCount)'));
      expect(reglas, contains('newCount <= maxCount || newCount <= oldCount'));
    });
  });
}
