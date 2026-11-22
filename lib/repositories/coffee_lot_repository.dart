import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/coffee_lot.dart';
import '../models/discover_filters.dart';
import '../models/lot_deletion.dart';
import '../utils/photo_cleanup.dart';
import '../utils/photo_limits.dart';
import 'pending_deletions.dart';
import 'repo_exception.dart';

class CatalogPage {
  final List<CoffeeLot> lotes;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hayMas;
  const CatalogPage(this.lotes, this.cursor, this.hayMas);
}

/// Colección `coffeeLots/{lotId}`.
class CoffeeLotRepository {
  static const tamanoPagina = 20;

  final FirebaseFirestore _db;

  /// Aviso (sin esperar respuesta) al Worker de limpieza tras encolar fotos retiradas.
  final Future<void> Function()? _alRetirarFotos;

  CoffeeLotRepository({FirebaseFirestore? db, Future<void> Function()? alRetirarFotos})
      : _db = db ?? FirebaseFirestore.instance,
        _alRetirarFotos = alRetirarFotos;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('coffeeLots');

  CoffeeLot _lote(DocumentSnapshot<Map<String, dynamic>> d) => CoffeeLot.fromMap(d.id, d.data() ?? {});

  /// Una página de lotes PUBLICADOS. Firestore solo filtra por `estado` y
  /// ordena por fecha o precio; el resto de filtros se aplica en el cliente
  /// sobre cada página (ver CatalogLogic y la sección de limitaciones del
  /// README). Los borradores nunca se piden: la consulta lleva
  /// `estado == publicado`, que es también lo que exigen las reglas.
  Future<CatalogPage> consultarCatalogo({
    DiscoverSort orden = DiscoverSort.relevancia,
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
  }) =>
      guardar(() async {
        Query<Map<String, dynamic>> q = _col.where('estado', isEqualTo: EstadoLote.publicado.name);
        switch (orden) {
          case DiscoverSort.precioAsc:
            q = q.orderBy('precioCOP');
          case DiscoverSort.precioDesc:
            q = q.orderBy('precioCOP', descending: true);
          default:
            q = q.orderBy('fechaPublicacion', descending: true);
        }
        if (despuesDe != null) q = q.startAfterDocument(despuesDe);
        final snap = await q.limit(tamanoPagina).get();
        return CatalogPage(
          snap.docs.map(_lote).toList(),
          snap.docs.isEmpty ? despuesDe : snap.docs.last,
          snap.docs.length == tamanoPagina,
        );
      });

  /// Todos los lotes de un vendedor (borradores incluidos). Solo el
  /// propietario puede pedirlos.
  Stream<List<CoffeeLot>> observarDeVendedor(String sellerId) {
    final s = _col.where('sellerId', isEqualTo: sellerId).snapshots().map((snap) {
      final lotes = snap.docs.map(_lote).toList();
      lotes.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
      return lotes;
    });
    return traducirErrores(s);
  }

  /// Estado de las eliminaciones de cafés de este vendedor, por id de lote
  /// (`users/{uid}/pendingLotDeletions`, que solo él puede leer). Es lo que distingue un café
  /// «en eliminación» de un borrador normal: `eliminar` deja el lote como borrador sin fotos
  /// hasta que el Worker lo borra. Incluye «completado» a propósito: así el café no reaparece
  /// un instante como borrador entre el cierre de la solicitud y el borrado del documento.
  Stream<Map<String, EstadoEliminacionLote>> observarEliminaciones(String uid) {
    final s = _db.collection('users').doc(uid).collection(PendingFileDeletions.coleccionLotes).snapshots().map((snap) {
      final estados = <String, EstadoEliminacionLote>{};
      for (final d in snap.docs) {
        final estado = EstadoEliminacionLote.desde(d.data()['estado']);
        if (estado != null) estados[d.id] = estado;
      }
      return estados;
    });
    return traducirErrores(s);
  }

  /// Lotes publicados de un vendedor (vista pública).
  Stream<List<CoffeeLot>> observarPublicadosDeVendedor(String sellerId) {
    final s = _col
        .where('sellerId', isEqualTo: sellerId)
        .where('estado', isEqualTo: EstadoLote.publicado.name)
        .snapshots()
        .map((snap) {
      final lotes = snap.docs.map(_lote).toList();
      lotes.sort((a, b) => (b.fechaPublicacion ?? DateTime(2000)).compareTo(a.fechaPublicacion ?? DateTime(2000)));
      return lotes;
    });
    return traducirErrores(s);
  }

  Future<int> contarPublicados(String sellerId) => guardar(() async {
        final agg = await _col
            .where('sellerId', isEqualTo: sellerId)
            .where('estado', isEqualTo: EstadoLote.publicado.name)
            .count()
            .get();
        return agg.count ?? 0;
      });

  /// Emite `null` si el lote no existe o no es visible para este usuario
  /// (borrador de otro vendedor).
  Stream<CoffeeLot?> observar(String lotId) {
    final s = _col.doc(lotId).snapshots().map((d) => d.exists ? _lote(d) : null);
    return traducirErrores(s);
  }

  Future<CoffeeLot?> obtener(String lotId) => guardar(() async {
        final d = await _col.doc(lotId).get();
        return d.exists ? _lote(d) : null;
      });

  /// Lotes publicados por id (para Guardados). La condición `estado` hace
  /// que la consulta cumpla las reglas aunque otros lotes sean borradores.
  Future<List<CoffeeLot>> publicadosPorIds(List<String> ids) => guardar(() async {
        final resultado = <CoffeeLot>[];
        for (var i = 0; i < ids.length; i += 30) {
          final trozo = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
          final snap = await _col
              .where(FieldPath.documentId, whereIn: trozo)
              .where('estado', isEqualTo: EstadoLote.publicado.name)
              .get();
          resultado.addAll(snap.docs.map(_lote));
        }
        return resultado;
      });

  /// Crea o actualiza un lote del vendedor autenticado. La fecha de
  /// publicación la pone el servidor la primera vez que se publica.
  /// Devuelve el id del lote.
  ///
  /// Un borrador no necesita fotos; publicar exige al menos una foto ya
  /// subida (URL remota). Es la misma regla de la pantalla, repetida aquí para
  /// que ningún camino publique un lote sin imagen.
  Future<String> guardarLote(CoffeeLot lote, {String? idExistente}) => guardar(() async {
        // Un café suspendido (por una eliminación de cuenta) o de estado desconocido no se guarda desde la app.
        if (!lote.editable) {
          throw const RepoException(RepoErrorKind.validacion, 'Este café no se puede modificar en su estado actual.');
        }
        if (lote.publicado && !lote.tieneFoto) {
          throw const RepoException(RepoErrorKind.validacion, 'Para publicar el café necesitas al menos una foto subida correctamente.');
        }
        final ref = idExistente == null ? _col.doc() : _col.doc(idExistente);
        // Límite de fotos (PhotoLimits.maxCafe). Un lote antiguo con más fotos
        // puede guardarse con las mismas o menos, pero no con más.
        final previo = idExistente == null ? null : await ref.get();
        final fotosPrevias = _contar(previo?.data()?['fotos']);
        final excesoFotos = PhotoLimits.validarCantidad(
          nuevo: lote.fotos.length,
          max: PhotoLimits.maxCafe,
          previo: fotosPrevias,
          galeria: false,
        );
        if (excesoFotos != null) throw RepoException(RepoErrorKind.validacion, excesoFotos);
        final datos = <String, dynamic>{
          ...lote.toEditableMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        // El lote y las solicitudes de borrado de las fotos que deja de usar se
        // confirman en UNA operación atómica: la foto nueva queda guardada a la vez
        // que se pide eliminar la anterior (nunca antes). El Worker, además,
        // comprueba que la foto vieja ya no esté referenciada.
        final batch = _db.batch();
        var retiradas = 0;
        if (idExistente == null) {
          datos['vendedorVerificado'] = false; // solo un proceso interno puede ponerlo en true
          datos['createdAt'] = FieldValue.serverTimestamp();
          datos['fechaPublicacion'] = lote.publicado ? FieldValue.serverTimestamp() : null;
          batch.set(ref, datos);
        } else {
          final yaTeniaFecha = previo?.data()?['fechaPublicacion'] != null;
          if (lote.publicado && !yaTeniaFecha) datos['fechaPublicacion'] = FieldValue.serverTimestamp();
          batch.update(ref, datos);
          retiradas = await PendingFileDeletions.encolar(
            db: _db,
            batch: batch,
            uid: lote.sellerId,
            fileIds: PhotoCleanup.retirados(
              previos: PhotoCleanup.idsDe(previo?.data()?['fotosStoragePaths']),
              actuales: lote.fotosStoragePaths,
            ),
            origen: OrigenFoto.lot,
            refId: ref.id,
          );
        }
        await batch.commit();
        if (retiradas > 0) pedirLimpiezaSinEsperar(_alRetirarFotos);
        return ref.id;
      });

  static int _contar(Object? lista) => lista is List ? lista.length : 0;

  /// PIDE eliminar un lote sin dejar fotos huérfanas ni copias históricas rotas. En UNA operación
  /// atómica: el lote pasa a borrador sin fotos (deja de verse en el catálogo), se encola la
  /// eliminación de cada una de sus fotos y se crea `users/{uid}/pendingLotDeletions/{lotId}`.
  /// El borrado real lo completa el Worker de limpieza: deja en null `loteFoto` en las solicitudes
  /// de interés y cotizaciones de ESE lote (la app no puede modificar ese historial), borra el
  /// lote y libera para su borrado las fotos que solo retenía el historial. Si la app se cierra
  /// a mitad, no se pierde nada: la operación es atómica y el Worker la termina (también por cron).
  Future<void> eliminar(String lotId) => guardar(() async {
        final ref = _col.doc(lotId);
        final datos = (await ref.get()).data();
        if (datos == null) return;
        final sellerId = datos['sellerId'];
        if (sellerId is! String) return;
        final ids = PhotoCleanup.retirados(previos: PhotoCleanup.idsDe(datos['fotosStoragePaths']), actuales: const <String>[]);
        final batch = _db.batch();
        batch.update(ref, {
          'estado': EstadoLote.borrador.name,
          'fotos': <String>[],
          'fotosStoragePaths': <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await PendingFileDeletions.encolar(db: _db, batch: batch, uid: sellerId, fileIds: ids, origen: OrigenFoto.lot, refId: lotId);
        await PendingFileDeletions.encolarBorradoDeLote(db: _db, batch: batch, uid: sellerId, lotId: lotId);
        // Repetir la eliminación también reabre las solicitudes de foto de ESTE lote que quedaron
        // «fallido» (el lote ya no tiene fotos, así que `encolar` no las vuelve a ver).
        await PendingFileDeletions.reabrirFotosFallidas(db: _db, batch: batch, uid: sellerId, refId: lotId, origen: OrigenFoto.lot, excluir: ids);
        await batch.commit();
        pedirLimpiezaSinEsperar(_alRetirarFotos);
      });
}
