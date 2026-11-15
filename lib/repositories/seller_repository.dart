import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/seller_profile.dart';
import '../utils/photo_cleanup.dart';
import '../utils/photo_limits.dart';
import 'pending_deletions.dart';
import 'repo_exception.dart';

/// Colección `sellerProfiles/{uid}` (perfil público del vendedor).
class SellerRepository {
  final FirebaseFirestore _db;

  /// Aviso (sin esperar respuesta) al Worker de limpieza tras encolar fotos retiradas.
  final Future<void> Function()? _alRetirarFotos;

  SellerRepository({FirebaseFirestore? db, Future<void> Function()? alRetirarFotos})
      : _db = db ?? FirebaseFirestore.instance,
        _alRetirarFotos = alRetirarFotos;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db.collection('sellerProfiles').doc(uid);

  Stream<SellerProfile?> observar(String sellerId) {
    return traducirErrores(_ref(sellerId).snapshots().map((s) {
      final d = s.data();
      return d == null ? null : SellerProfile.fromMap(s.id, d);
    }));
  }

  Future<SellerProfile?> obtener(String sellerId) => guardar(() async {
        final s = await _ref(sellerId).get();
        final d = s.data();
        return d == null ? null : SellerProfile.fromMap(s.id, d);
      });

  /// Crea o actualiza el perfil del propietario. `verificado`,
  /// `calificacionPromedio` y `numOperaciones` nunca se envían desde la app.
  Future<void> guardarPerfil(SellerProfile perfil) => guardar(() async {
        final ref = _ref(perfil.id);
        final previo = await ref.get();
        final existe = previo.exists;
        // Límite de la galería (PhotoLimits.maxGaleriaMarca); la foto principal
        // no cuenta. Un perfil antiguo con más fotos puede guardarse con las
        // mismas o menos, pero no con más.
        final galeriaPrevia = previo.data()?['galeria'];
        final excesoGaleria = PhotoLimits.validarCantidad(
          nuevo: perfil.galeria.length,
          max: PhotoLimits.maxGaleriaMarca,
          previo: galeriaPrevia is List ? galeriaPrevia.length : 0,
          galeria: true,
        );
        if (excesoGaleria != null) throw RepoException(RepoErrorKind.validacion, excesoGaleria);
        // El perfil y las solicitudes de borrado de las fotos que deja de usar (la
        // principal sustituida o quitada, fotos de galería quitadas) se confirman en
        // UNA operación atómica: la foto nueva queda guardada a la vez que se pide
        // eliminar la anterior, nunca antes. En ese mismo lote se reabren además las
        // solicitudes de fotos del perfil que el Worker dejó «fallido» (p. ej. por una
        // credencial de ImageKit mal puesta), aunque esas fotos ya no estén en el perfil:
        // el cron no procesa «fallido» a propósito, así que solo la app puede reabrirlas.
        final batch = _db.batch();
        var encoladas = 0; // nuevas o reabiertas por `encolar` (fotos que este guardado retira)
        var reabiertas = 0; // antiguas «fallido» reabiertas por `reabrirFotosFallidas`
        if (existe) {
          batch.update(ref, {
            ...perfil.toEditableMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          final datosPrevios = previo.data();
          final principalNueva = perfil.fotoPrincipalStoragePath;
          // Se calcula UNA sola vez y se reutiliza: `encolar` ya puede reabrir una solicitud
          // «fallido» de una foto que se retira ahora, y `excluir` evita escribir dos veces ese
          // mismo documento en el lote atómico.
          final retirados = PhotoCleanup.retirados(
            previos: [
              ...PhotoCleanup.idsDe([datosPrevios?['fotoPrincipalStoragePath']]),
              ...PhotoCleanup.idsDe(datosPrevios?['galeriaStoragePaths']),
            ],
            actuales: [if (principalNueva != null) principalNueva, ...perfil.galeriaStoragePaths],
          );
          encoladas = await PendingFileDeletions.encolar(
            db: _db,
            batch: batch,
            uid: perfil.id,
            fileIds: retirados,
            origen: OrigenFoto.profile,
            refId: perfil.id,
          );
          reabiertas = await PendingFileDeletions.reabrirFotosFallidas(
            db: _db,
            batch: batch,
            uid: perfil.id,
            refId: perfil.id,
            origen: OrigenFoto.profile,
            excluir: retirados,
          );
        } else {
          batch.set(ref, {
            ...perfil.toEditableMap(),
            'verificado': false,
            'calificacionPromedio': 0,
            'numOperaciones': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        // Aviso no bloqueante: si falla, el guardado ya está confirmado y el cron lo recupera.
        if (encoladas > 0 || reabiertas > 0) pedirLimpiezaSinEsperar(_alRetirarFotos);
      });
}
