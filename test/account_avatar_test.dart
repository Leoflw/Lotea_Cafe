import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/seller_profile.dart';
import 'package:lotea_cafe/repositories/seller_repository.dart';
import 'package:lotea_cafe/utils/avatar_logic.dart';
import 'package:lotea_cafe/widgets/avatar_circular.dart';

const _fotoA = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/profile/profile_a.jpg';
const _fotoB = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/profile/profile_b.jpg';
const _fotoOtro = 'https://ik.imagekit.io/demo/lotea-cafe/users/u2/profile/profile_otro.jpg';

const _vendedor = AppUser(uid: 'u1', email: 'v@x.co', nombre: 'dyd', rol: UserRole.vendedor);
const _comprador = AppUser(uid: 'b1', email: 'b@x.co', nombre: 'juan', rol: UserRole.comprador);

SellerProfile _perfil({String id = 'u1', String? foto}) => SellerProfile(
      id: id,
      usuarioId: id,
      nombreMarca: 'dyd',
      fincaPrincipal: 'cf',
      fotoPrincipal: foto,
      region: 'Antioquia',
      departamento: 'Antioquia',
    );

Widget _app(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));

void main() {
  group('AvatarLogic: qué foto va en el círculo de «Mi cuenta»', () {
    test('1. un vendedor con fotoPrincipal válida ve esa fotografía', () {
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: _perfil(foto: _fotoA)), _fotoA);
    });

    test('2. un vendedor sin foto ve la inicial (no hay foto que mostrar)', () {
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: _perfil()), isNull);
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: null), isNull);
      expect(AvatarLogic.inicial('dyd'), 'D');
      expect(AvatarLogic.inicial('  el pepe'), 'E');
      expect(AvatarLogic.inicial(''), '?');
    });

    test('una foto vacía o que no es una URL no se usa', () {
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: _perfil(foto: '')), isNull);
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: _perfil(foto: 'foto.jpg')), isNull);
    });

    test('4. un comprador nunca muestra la foto de un vendedor', () {
      expect(AvatarLogic.fotoDeCuenta(usuario: _comprador, perfil: _perfil(foto: _fotoA)), isNull);
    });

    test('nunca se usa la foto de otro vendedor (perfil de otro documento)', () {
      expect(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: _perfil(id: 'u2', foto: _fotoOtro)), isNull);
    });
  });

  group('5. cambiar la foto de marca se refleja sin cerrar sesión', () {
    test('el perfil se escucha en tiempo real y el avatar toma la foto nueva', () async {
      final repo = SellerRepository(db: FakeFirebaseFirestore());
      await repo.guardarPerfil(_perfil(foto: _fotoA));

      final fotos = <String?>[];
      final sub = repo.observar('u1').listen((p) => fotos.add(AvatarLogic.fotoDeCuenta(usuario: _vendedor, perfil: p)));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(fotos.last, _fotoA);

      await repo.guardarPerfil(_perfil(foto: _fotoB)); // el vendedor guarda otra foto de marca
      await pumpEventQueue();
      expect(fotos.last, _fotoB);
    });

    testWidgets('el círculo pide la foto nueva cuando cambia la URL', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: _fotoA, nombre: 'dyd', radius: 44)));
      expect(((tester.widget<Image>(find.byType(Image))).image as NetworkImage).url, startsWith(_fotoA));
      await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: _fotoB, nombre: 'dyd', radius: 44)));
      expect(((tester.widget<Image>(find.byType(Image))).image as NetworkImage).url, startsWith(_fotoB));
    });
  });

  group('AvatarCircular', () {
    testWidgets('con foto de ImageKit la pide redimensionada al tamaño del círculo', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: _fotoA, nombre: 'dyd', radius: 44)));
      final imagen = tester.widget<Image>(find.byType(Image));
      expect(imagen.image, isA<NetworkImage>());
      // 88 px × densidad 1.0 → ancho estándar 160.
      expect((imagen.image as NetworkImage).url, '$_fotoA?tr=w-160,q-80');
      expect(find.byType(ClipOval), findsOneWidget, reason: 'recorte circular');
    });

    testWidgets('2. sin foto muestra la inicial y no intenta cargar ninguna imagen', (tester) async {
      await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: null, nombre: 'dyd', radius: 44)));
      expect(find.text('D'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('3. si ImageKit no responde o la imagen falla se muestra la inicial sin romper la pantalla', (tester) async {
      // En flutter_test las peticiones HTTP reales se bloquean: la carga falla.
      await tester.runAsync(() async {
        await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: _fotoA, nombre: 'dyd', radius: 44)));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.text('D'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una ruta local inexistente tampoco rompe: queda la inicial', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(_app(const AvatarCircular(fotoUrl: '/no/existe/foto.jpg', nombre: 'dyd', radius: 22)));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('D'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
