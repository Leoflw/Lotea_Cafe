// Etapa 6 — modelos: estado de cuenta (AppUser) y estados de café (EstadoLote).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotea_cafe/models/app_user.dart';
import 'package:lotea_cafe/models/coffee_lot.dart';
import 'package:lotea_cafe/repositories/coffee_lot_repository.dart';
import 'package:lotea_cafe/repositories/repo_exception.dart';
import 'package:lotea_cafe/repositories/user_repository.dart';

Map<String, dynamic> _usuario([Map<String, dynamic> extra = const {}]) => {
      'email': 'ana@x.co',
      'nombre': 'Ana',
      'rol': 'vendedor',
      'onboardingCompleto': true,
      ...extra,
    };

void main() {
  group('AppUser: estado de cuenta', () {
    test('sin el campo cuentaEstado la cuenta es ACTIVA (usuarios anteriores a la etapa 6)', () {
      final u = AppUser.fromMap('ana', _usuario());
      expect(u.cuentaEstado, CuentaEstado.activa);
      expect(u.cuentaActiva, isTrue);
      expect(u.operacionesBloqueadas, isFalse);
      expect(u.eliminacionSolicitadaAt, isNull);
      expect(u.eliminacionProgramadaAt, isNull);
    });

    test('cuentaEstado «activa» explícito, con las fechas a null (tras cancelar)', () {
      final u = AppUser.fromMap('ana', _usuario({'cuentaEstado': 'activa', 'eliminacionSolicitadaAt': null, 'eliminacionProgramadaAt': null}));
      expect(u.cuentaEstado, CuentaEstado.activa);
      expect(u.eliminacionProgramadaAt, isNull);
    });

    test('cuenta «eliminacionPendiente» con sus fechas', () {
      final pedida = DateTime.utc(2026, 11, 14, 12);
      final programada = DateTime.utc(2026, 11, 29, 12);
      final u = AppUser.fromMap('ana', _usuario({
        'cuentaEstado': 'eliminacionPendiente',
        'eliminacionSolicitadaAt': Timestamp.fromDate(pedida),
        'eliminacionProgramadaAt': Timestamp.fromDate(programada),
      }));
      expect(u.cuentaEstado, CuentaEstado.eliminacionPendiente);
      expect(u.eliminacionPendiente, isTrue);
      expect(u.operacionesBloqueadas, isTrue);
      expect(u.eliminacionSolicitadaAt!.toUtc(), pedida);
      expect(u.eliminacionProgramadaAt!.toUtc(), programada);
    });

    test('un valor desconocido se trata de forma conservadora: NO es activa y bloquea', () {
      for (final raro in ['ELIMINANDO', 'ACTIVA', '', 'otraCosa', 7, true]) {
        final u = AppUser.fromMap('ana', _usuario({'cuentaEstado': raro}));
        expect(u.cuentaEstado, CuentaEstado.desconocida, reason: '$raro');
        expect(u.cuentaActiva, isFalse, reason: '$raro');
        expect(u.operacionesBloqueadas, isTrue, reason: '$raro');
      }
    });

    test('plazoVencido: antes de la fecha no; en la fecha y después sí; sin fecha no', () {
      final programada = DateTime.utc(2026, 11, 29, 12);
      final u = AppUser.fromMap('ana', _usuario({'cuentaEstado': 'eliminacionPendiente', 'eliminacionProgramadaAt': Timestamp.fromDate(programada)}));
      expect(u.plazoVencido(programada.subtract(const Duration(seconds: 1))), isFalse);
      expect(u.plazoVencido(programada), isTrue);
      expect(u.plazoVencido(programada.add(const Duration(days: 3))), isTrue);
      expect(AppUser.fromMap('ana', _usuario()).plazoVencido(DateTime.utc(2030)), isFalse);
    });

    test('copyWith conserva el estado de cuenta y las fechas', () {
      final u = AppUser.fromMap('ana', _usuario({'cuentaEstado': 'eliminacionPendiente', 'eliminacionProgramadaAt': Timestamp.fromDate(DateTime.utc(2026, 11, 29))}));
      final c = u.copyWith(nombre: 'Ana B');
      expect(c.cuentaEstado, CuentaEstado.eliminacionPendiente);
      expect(c.eliminacionProgramadaAt, u.eliminacionProgramadaAt);
    });

    test('los campos de control NO forman parte de lo que el cliente escribe', () {
      final u = AppUser.fromMap('ana', _usuario({'cuentaEstado': 'eliminacionPendiente'}));
      final editable = u.toEditableMap();
      for (final k in ['cuentaEstado', 'eliminacionSolicitadaAt', 'eliminacionProgramadaAt']) {
        expect(editable.containsKey(k), isFalse, reason: k);
      }
    });

    test('UserRepository.actualizar no modifica cuentaEstado ni las fechas', () async {
      final db = FakeFirebaseFirestore();
      final programada = Timestamp.fromDate(DateTime.utc(2026, 11, 29));
      await db.collection('users').doc('ana').set(_usuario({'uid': 'ana', 'cuentaEstado': 'eliminacionPendiente', 'eliminacionProgramadaAt': programada}));
      final repo = UserRepository(db: db);
      final u = (await repo.obtener('ana'))!;
      await repo.actualizar(u.copyWith(nombre: 'Ana Nueva'));
      final data = (await db.collection('users').doc('ana').get()).data()!;
      expect(data['nombre'], 'Ana Nueva');
      expect(data['cuentaEstado'], 'eliminacionPendiente');
      expect(data['eliminacionProgramadaAt'], programada);
    });
  });

  group('EstadoLote', () {
    Map<String, dynamic> lote(Object? estado) => {
          'sellerId': 'ana', 'nombre': 'Caturra', 'variedades': ['Caturra'], 'proceso': 'Lavado', 'precioCOP': 32000,
          'unidad': 'kg', 'fotos': <String>[], 'fotosStoragePaths': <String>[], if (estado != null) 'estado': estado,
        };

    test('reconoce borrador, publicado y suspendido', () {
      expect(CoffeeLot.fromMap('1', lote('borrador')).estado, EstadoLote.borrador);
      expect(CoffeeLot.fromMap('1', lote('publicado')).estado, EstadoLote.publicado);
      final s = CoffeeLot.fromMap('1', lote('suspendido'));
      expect(s.estado, EstadoLote.suspendido);
      expect(s.suspendido, isTrue);
      expect(s.publicado, isFalse);
      expect(s.editable, isFalse);
    });

    test('un estado desconocido NO se convierte en borrador: no es editable ni publicable', () {
      for (final raro in ['archivado', 'Publicado', '', 'desconocido', 3]) {
        final l = CoffeeLot.fromMap('1', lote(raro));
        expect(l.estado, EstadoLote.desconocido, reason: '$raro');
        expect(l.estado, isNot(EstadoLote.borrador), reason: '$raro');
        expect(l.editable, isFalse, reason: '$raro');
        expect(l.publicado, isFalse, reason: '$raro');
      }
    });

    test('un documento antiguo SIN campo estado sigue leyéndose como borrador', () {
      expect(CoffeeLot.fromMap('1', lote(null)).estado, EstadoLote.borrador);
    });

    test('borrador y publicado son editables', () {
      expect(CoffeeLot.fromMap('1', lote('borrador')).editable, isTrue);
      expect(CoffeeLot.fromMap('1', lote('publicado')).editable, isTrue);
    });

    test('guardarLote rechaza un café suspendido o de estado desconocido y no escribe nada', () async {
      final db = FakeFirebaseFirestore();
      final repo = CoffeeLotRepository(db: db);
      for (final estado in [EstadoLote.suspendido, EstadoLote.desconocido]) {
        final l = CoffeeLot.fromMap('1', lote('borrador')).copyWith(estado: estado);
        await expectLater(
          repo.guardarLote(l, idExistente: 'x'),
          throwsA(isA<RepoException>().having((e) => e.tipo, 'tipo', RepoErrorKind.validacion)),
        );
      }
      expect((await db.collection('coffeeLots').get()).docs, isEmpty);
    });
  });
}
