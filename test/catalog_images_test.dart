import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/utils/image_source.dart';
import 'package:lotea_cafe/widgets/app_image.dart';

const _url = 'https://ik.imagekit.io/demo/lotea-cafe/users/u1/lots/lot_a.jpg';

void main() {
  group('URLs de ImageKit', () {
    test('se reconocen los dominios de ImageKit y se descartan los parecidos', () {
      expect(ImageKitUrls.esImageKit(_url), isTrue);
      expect(ImageKitUrls.esImageKit('https://ik.imagekit.io/x/y.jpg'), isTrue);
      expect(ImageKitUrls.esImageKit('http://ik.imagekit.io/x/y.jpg'), isFalse, reason: 'solo HTTPS');
      expect(ImageKitUrls.esImageKit('https://imagekit.io.evil.com/x.jpg'), isFalse);
      expect(ImageKitUrls.esImageKit('https://evil.com/ik.imagekit.io/x.jpg'), isFalse);
      expect(ImageKitUrls.esImageKit('https://example.com/foto.jpg'), isFalse);
      expect(ImageKitUrls.esImageKit('no es una url'), isFalse);
    });

    test('un dominio propio configurado como URL endpoint también se reconoce', () {
      expect(ImageKitUrls.esImageKit('https://fotos.loteacafe.co/a.jpg', urlEndpoint: 'https://fotos.loteacafe.co'), isTrue);
      expect(ImageKitUrls.esImageKit('https://fotos.loteacafe.co/a.jpg'), isFalse);
    });

    test('se piden fotos del tamaño que se pinta (ancho estándar y calidad 80)', () {
      expect(ImageKitUrls.optimizada(_url, 120), '$_url?tr=w-160,q-80');
      expect(ImageKitUrls.optimizada(_url, 300), '$_url?tr=w-320,q-80');
      expect(ImageKitUrls.optimizada(_url, 720), '$_url?tr=w-720,q-80');
      expect(ImageKitUrls.optimizada(_url, 5000), '$_url?tr=w-1600,q-80');
      expect(ImageKitUrls.optimizada('$_url?v=2', 300), '$_url?v=2&tr=w-320,q-80');
    });

    test('no se toca una URL con transformación propia ni una que no es de ImageKit', () {
      expect(ImageKitUrls.optimizada('$_url?tr=w-50', 300), '$_url?tr=w-50');
      expect(ImageKitUrls.optimizada('https://example.com/a.jpg', 300), 'https://example.com/a.jpg');
    });
  });

  group('imageProviderFor', () {
    test('assets, archivos locales y URLs remotas', () {
      expect(imageProviderFor('assets/branding/lotea_cafe_symbol.png'), isA<AssetImage>());
      expect(imageProviderFor('/data/user/0/app/cache/foto.jpg'), isA<FileImage>());
      final remota = imageProviderFor(_url, anchoPx: 300);
      expect(remota, isA<NetworkImage>());
      expect((remota as NetworkImage).url, '$_url?tr=w-320,q-80');
    });

    test('sin anchoPx la URL remota se usa tal cual', () {
      expect((imageProviderFor(_url) as NetworkImage).url, _url);
    });
  });

  group('AppImage en el catálogo', () {
    Widget app(Widget hijo) => MaterialApp(home: Scaffold(body: Center(child: hijo)));

    testWidgets('una foto de ImageKit se pide por red con el tamaño de la tarjeta', (tester) async {
      tester.view.devicePixelRatio = 1.0; // por defecto flutter_test usa 3.0
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(const AppImage(path: _url, width: 100, height: 100, ampliable: false)));
      final imagen = tester.widget<Image>(find.byType(Image));
      expect(imagen.image, isA<NetworkImage>());
      // 100 px lógicos × densidad 1.0 → ancho estándar 160.
      expect((imagen.image as NetworkImage).url, '$_url?tr=w-160,q-80');
    });

    testWidgets('sin ancho fijo (tarjeta a todo el ancho) pide 720 px', (tester) async {
      await tester.pumpWidget(app(const SizedBox(width: 300, height: 200, child: AppImage(path: _url, ampliable: false))));
      final imagen = tester.widget<Image>(find.byType(Image));
      expect((imagen.image as NetworkImage).url, '$_url?tr=w-720,q-80');
    });

    testWidgets('mientras la imagen carga o si falla se ve el placeholder, nunca un hueco ni un crash', (tester) async {
      // En flutter_test las peticiones HTTP reales se bloquean: la carga falla y
      // AppImage debe mostrar su placeholder de «Sin fotografía».
      await tester.runAsync(() async {
        await tester.pumpWidget(app(const SizedBox(width: 300, height: 200, child: AppImage(path: _url, ampliable: false))));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Sin fotografía'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un lote sin foto muestra el placeholder', (tester) async {
      await tester.pumpWidget(app(const SizedBox(width: 300, height: 200, child: AppImage(path: null, ampliable: false))));
      expect(find.text('Sin fotografía'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
