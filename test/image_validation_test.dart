import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/utils/image_validation.dart';

Uint8List _con(List<int> cabecera, {int total = 64}) {
  final b = Uint8List(total);
  b.setRange(0, cabecera.length, cabecera);
  return b;
}

final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0];
final _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
final _webp = [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50];

void main() {
  group('tipo por contenido (no por extensión)', () {
    test('reconoce JPEG, PNG y WebP', () {
      expect(ImageValidation.validar(_con(_jpeg)), ImageType.jpeg);
      expect(ImageValidation.validar(_con(_png)), ImageType.png);
      expect(ImageValidation.validar(_con(_webp)), ImageType.webp);
    });

    test('cada tipo tiene su mime y extensión', () {
      expect(ImageType.jpeg.mime, 'image/jpeg');
      expect(ImageType.png.mime, 'image/png');
      expect(ImageType.webp.mime, 'image/webp');
      expect(ImageType.webp.extension, 'webp');
    });

    test('rechaza GIF, PDF y texto', () {
      final gif = _con([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      final pdf = _con([0x25, 0x50, 0x44, 0x46, 0x2D]);
      final txt = Uint8List.fromList('hola mundo, esto no es una imagen'.codeUnits);
      for (final b in [gif, pdf, txt]) {
        expect(
          () => ImageValidation.validar(b),
          throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion).having((e) => e.mensaje, 'mensaje', contains('JPEG, PNG o WebP'))),
        );
      }
    });

    test('un RIFF que no es WebP (p. ej. WAV) se rechaza', () {
      final wav = _con([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      expect(() => ImageValidation.validar(wav), throwsA(isA<RepoException>()));
    });

    test('rechaza un archivo vacío o demasiado corto', () {
      expect(() => ImageValidation.validar(Uint8List(0)), throwsA(isA<RepoException>()));
      expect(() => ImageValidation.validar(Uint8List.fromList([0xFF, 0xD8])), throwsA(isA<RepoException>()));
    });
  });

  group('tamaño', () {
    test('el límite es de 5 MB', () {
      expect(ImageValidation.maxBytes, 5 * 1024 * 1024);
    });

    test('acepta exactamente 5 MB', () {
      expect(ImageValidation.validar(_con(_jpeg, total: ImageValidation.maxBytes)), ImageType.jpeg);
    });

    test('rechaza 5 MB + 1 byte con un mensaje claro', () {
      expect(
        () => ImageValidation.validar(_con(_jpeg, total: ImageValidation.maxBytes + 1)),
        throwsA(isA<RepoException>().having((e) => e.mensaje, 'mensaje', contains('5 MB'))),
      );
    });
  });

  test('la compresión al elegir la foto reduce el lado máximo y la calidad', () {
    expect(ImageValidation.pickerMaxSide, lessThanOrEqualTo(2000));
    expect(ImageValidation.pickerQuality, inInclusiveRange(60, 90));
  });
}
