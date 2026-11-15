import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// De dónde sale la foto que se pide borrar (lo valida `firestore.rules`).
enum OrigenFoto {
  lot,
  profile;

  String get wire => name;
}

/// Cola de eliminación de fotos: `users/{uid}/pendingFileDeletions/{fileId}`.
///
/// La app SOLO pide el borrado; no toca ImageKit. El Worker de limpieza
/// (`cloudflare/imagekit-cleanup`) valida cada solicitud (dueño del archivo y
/// que ningún lote o perfil lo use) y es el único que borra y escribe el estado.
class PendingFileDeletions {
  PendingFileDeletions._();

  static const coleccion = 'pendingFileDeletions';
  static const coleccionLotes = 'pendingLotDeletions';

  static DocumentReference<Map<String, dynamic>> ref(FirebaseFirestore db, String uid, String fileId) =>
      db.collection('users').doc(uid).collection(coleccion).doc(fileId);

  /// Añade a [batch] una solicitud por cada id, para que se confirme EN LA MISMA
  /// operación atómica que guarda el documento con la foto nueva: o se guardan
  /// las dos cosas o ninguna, y nunca se pide borrar la foto vieja sin que la
  /// nueva esté ya guardada.
  ///
  /// - Un id que ya tiene solicitud no se duplica (idempotente).
  /// - Una solicitud que el Worker dejó «enUso» o «fallido» se vuelve a pedir. Una «retenida»
  ///   (solo la usa el historial de negociaciones) la revisa el Worker por su cuenta.
  /// Devuelve cuántas solicitudes quedaron en el lote.
  static Future<int> encolar({
    required FirebaseFirestore db,
    required WriteBatch batch,
    required String uid,
    required Iterable<String> fileIds,
    required OrigenFoto origen,
    String? refId,
  }) async {
    var n = 0;
    for (final id in fileIds) {
      final destino = ref(db, uid, id);
      final existente = await destino.get();
      if (existente.exists) {
        final estado = existente.data()?['estado'];
        if (estado == 'enUso' || estado == 'fallido') {
          batch.update(destino, {'estado': 'pendiente', 'createdAt': FieldValue.serverTimestamp()});
          n++;
        }
        continue;
      }
      batch.set(destino, {
        'fileId': id,
        'origen': origen.wire,
        if (refId != null) 'refId': refId,
        'estado': 'pendiente',
        'createdAt': FieldValue.serverTimestamp(),
      });
      n++;
    }
    return n;
  }

  /// Reabre (vuelve a «pendiente») las solicitudes de borrado de foto de ESTA persona que el
  /// Worker dejó «fallido». Hace falta porque `encolar` solo mira las fotos que un guardado
  /// retira AHORA: una foto cuya solicitud falló y que ya no está en ningún documento no
  /// volvería a pedirse nunca. Filtros opcionales (todos se combinan):
  ///  - [refId]: solo las de ese lote o perfil;
  ///  - [origen]: solo las de ese origen (`lot` o `profile`). Una solicitud de otro origen NO se
  ///    reabre aunque coincida su `refId`, y una sin campo `origen` tampoco (se descarta por prudencia);
  ///  - [excluir]: ids que `encolar` ya trata en el mismo lote atómico, para no escribir dos veces el
  ///    mismo documento en un único lote (las reglas exigen «fallido» en el estado previo, y una
  ///    segunda escritura sobre el mismo documento podría rechazarse).
  ///
  /// Solo toca `estado` y `createdAt` (lo único que permiten las reglas): el contador de
  /// intentos y el último error los reinicia el Worker al reclamarla. No reabre «completado»,
  /// «retenida», «enUso» ni «procesando», y nunca toca la cola de otra persona.
  static Future<int> reabrirFotosFallidas({
    required FirebaseFirestore db,
    required WriteBatch batch,
    required String uid,
    String? refId,
    OrigenFoto? origen,
    Iterable<String> excluir = const <String>[],
  }) async {
    final omitir = excluir.toSet();
    final fallidas = await db.collection('users').doc(uid).collection(coleccion).where('estado', isEqualTo: 'fallido').get();
    var n = 0;
    for (final d in fallidas.docs) {
      if (omitir.contains(d.id)) continue;
      if (refId != null && d.data()['refId'] != refId) continue;
      if (origen != null && d.data()['origen'] != origen.wire) continue;
      batch.update(d.reference, {'estado': 'pendiente', 'createdAt': FieldValue.serverTimestamp()});
      n++;
    }
    return n;
  }

  /// Añade a [batch] la solicitud de ELIMINAR un lote (`users/{uid}/pendingLotDeletions/{lotId}`).
  /// El Worker de limpieza deja en null `loteFoto` en las solicitudes de interés y cotizaciones
  /// de ese lote y después borra el lote; la app no puede tocar ese historial. Idempotente:
  /// una solicitud ya existente no se duplica (solo se reabre si quedó «fallido»).
  static Future<void> encolarBorradoDeLote({
    required FirebaseFirestore db,
    required WriteBatch batch,
    required String uid,
    required String lotId,
  }) async {
    final destino = db.collection('users').doc(uid).collection(coleccionLotes).doc(lotId);
    final existente = await destino.get();
    if (existente.exists) {
      if (existente.data()?['estado'] == 'fallido') {
        batch.update(destino, {'estado': 'pendiente', 'createdAt': FieldValue.serverTimestamp()});
      }
      return;
    }
    batch.set(destino, {'lotId': lotId, 'estado': 'pendiente', 'createdAt': FieldValue.serverTimestamp()});
  }
}

/// Avisa al Worker de que hay solicitudes nuevas SIN esperar su respuesta y sin
/// que un fallo afecte a lo que la persona acaba de guardar. Si el aviso se
/// pierde, la solicitud sigue en la cola y el cron del Worker la procesa.
void pedirLimpiezaSinEsperar(Future<void> Function()? aviso) {
  if (aviso == null) return;
  unawaited(Future<void>(() => aviso()).catchError((Object _) {}));
}
