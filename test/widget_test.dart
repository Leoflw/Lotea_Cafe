import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lotea_cafe/main.dart';
import 'package:lotea_cafe/screens/config/config_pending_screen.dart';
import 'package:lotea_cafe/services/firebase_bootstrap.dart';

// Estas pruebas NO usan Firebase real: LoteaCafeApp recibe el resultado de
// inicialización ya resuelto, así que con un estado distinto de «listo» no
// crea repositorios ni toca FirebaseAuth/Firestore. El flujo con sesión se
// probaría inyectando repositorios falsos (hoy main.dart los crea
// internamente; no se cambió esa arquitectura).
void main() {
  setUp(() {
    // Evita que el tema intente descargar fuentes durante las pruebas.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('sin configuración de Firebase muestra la pantalla de configuración pendiente', (tester) async {
    await tester.pumpWidget(
      const LoteaCafeApp(
        inicial: FirebaseInitResult(FirebaseInitStatus.configuracionPendiente, 'sin google-services.json'),
      ),
    );

    expect(find.text('Falta conectar Firebase'), findsOneWidget);
    expect(find.textContaining('FIREBASE_SETUP.md'), findsOneWidget);
    expect(find.textContaining('sin google-services.json'), findsOneWidget);
    // No existe modo demo ni acceso rápido.
    expect(find.text('Iniciar sesión'), findsNothing);
    expect(find.textContaining('demo', findRichText: true), findsNothing);
  });

  testWidgets('un fallo de inicialización se informa como error de conexión', (tester) async {
    await tester.pumpWidget(
      const LoteaCafeApp(inicial: FirebaseInitResult(FirebaseInitStatus.fallo, 'network')),
    );

    expect(find.text('No se pudo conectar con Firebase'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('el botón Reintentar invoca la acción recibida', (tester) async {
    var llamadas = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ConfigPendingScreen(
          resultado: const FirebaseInitResult(FirebaseInitStatus.configuracionPendiente),
          onReintentar: () => llamadas++,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(llamadas, 1);
  });
}
