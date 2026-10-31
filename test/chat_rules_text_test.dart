import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// OJO: esto NO es una prueba de reglas de seguridad. Solo comprueba que el
/// TEXTO de firestore.rules conserva las condiciones clave del estado del chat
/// (evita que se borren por accidente). El comportamiento real se prueba contra
/// el emulador en `rules-tests/` (npm test).
void main() {
  late String reglas;
  setUpAll(() => reglas = File('firestore.rules').readAsStringSync());

  test('el último mensaje exige un mensaje nuevo creado en la misma operación', () {
    for (final fragmento in [
      '!exists(newMessagePath())',
      'existsAfter(newMessagePath())',
      'getAfter(newMessagePath()).data.senderId == uid()',
      'getAfter(newMessagePath()).data.createdAt == request.time',
      'incoming().ultimoMensajeDe == uid()',
      'incoming().ultimoMensajeAt == request.time',
      "touchesOnly(['ultimoMensajeAt', 'ultimoMensajeDe', 'ultimoMensajeId'])",
    ]) {
      expect(reglas, contains(fragmento));
    }
  });

  test('cada participante solo escribe su marca de lectura', () {
    expect(reglas, contains("isBuyerOfRequest() && touchesOnly(['leidoComprador'])"));
    expect(reglas, contains("isSellerOfRequest() && touchesOnly(['leidoVendedor'])"));
  });
}
