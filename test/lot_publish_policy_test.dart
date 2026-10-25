import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/utils/lot_publish_policy.dart';

void main() {
  test('un borrador no exige ninguna foto', () {
    expect(LotPublishPolicy.motivoBloqueo(publicar: false, fotosSubidas: 0, fotosFallidas: 0), isNull);
  });

  test('un borrador tampoco se bloquea porque una subida falló', () {
    expect(LotPublishPolicy.motivoBloqueo(publicar: false, fotosSubidas: 0, fotosFallidas: 2), isNull);
  });

  test('publicar sin fotos se bloquea', () {
    expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: 0, fotosFallidas: 0), contains('al menos una foto'));
  });

  test('publicar con una imagen subida correctamente se permite', () {
    expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: 1, fotosFallidas: 0), isNull);
  });

  test('publicar con fotos pendientes por un fallo se bloquea, aunque haya otras subidas', () {
    expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: 2, fotosFallidas: 1), contains('1 foto'));
    expect(LotPublishPolicy.motivoBloqueo(publicar: true, fotosSubidas: 0, fotosFallidas: 3), contains('3 fotos'));
  });
}
