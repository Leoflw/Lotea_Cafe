import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/coffee_lot.dart';
import '../models/discover_filters.dart';
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
  CoffeeLotRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

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
        if (lote.publicado && !lote.tieneFoto) {
          throw const RepoException(RepoErrorKind.validacion, 'Para publicar el café necesitas al menos una foto subida correctamente.');
        }
        final ref = idExistente == null ? _col.doc() : _col.doc(idExistente);
        final datos = <String, dynamic>{
          ...lote.toEditableMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (idExistente == null) {
          datos['vendedorVerificado'] = false; // solo un proceso interno puede ponerlo en true
          datos['createdAt'] = FieldValue.serverTimestamp();
          datos['fechaPublicacion'] = lote.publicado ? FieldValue.serverTimestamp() : null;
          await ref.set(datos);
        } else {
          final previo = await ref.get();
          final yaTeniaFecha = previo.data()?['fechaPublicacion'] != null;
          if (lote.publicado && !yaTeniaFecha) datos['fechaPublicacion'] = FieldValue.serverTimestamp();
          await ref.update(datos);
        }
        return ref.id;
      });

  Future<void> eliminar(String lotId) => guardar(() => _col.doc(lotId).delete());
}
