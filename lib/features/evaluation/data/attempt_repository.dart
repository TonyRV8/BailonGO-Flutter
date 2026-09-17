import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_constants.dart';
import '../engine/dtw_result.dart';

/// Persiste los intentos en la colección HISTORY (doc 5.3.3). La mejor marca
/// (RN-04) se deriva como el máximo de `scores.total` por paso, así que basta
/// con guardar cada intento.
///
/// Offline-first (doc 5.3.3.2): la escritura va primero a la cache local de
/// Firestore (no se espera el ack del servidor); el SDK la sincroniza solo
/// cuando hay red, con last-write-wins.
class AttemptRepository {
  AttemptRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> save({
    required String uid,
    required String pasoId,
    required DtwResult result,
  }) async {
    final doc = _firestore.collection(AppConstants.historyCollection).doc();
    // No se espera el Future de red: la cache local persiste el intento al
    // instante y el SDK lo sube cuando haya conexión.
    unawaitedWrite(doc.set({
      'uid': uid,
      'pasoId': pasoId,
      'scores': {
        'ritmo': result.rhythmScore.toDouble(),
        'alineacion': result.alignmentScore.toDouble(),
        'total': result.score.toDouble(),
        // Desglose por tiempo (inicio/medio/final).
        'segmentos': [
          for (var s = 0; s < 3; s++)
            {
              'ritmo': result.segmentRhythm[s].toDouble(),
              'alineacion': result.segmentAlignment[s].toDouble(),
              'total': result.segmentScore[s].toDouble(),
            },
        ],
      },
      'deviceInfo': <String, dynamic>{},
      'timestamp': FieldValue.serverTimestamp(),
      'synced': true,
    }));
  }

  /// TEMPORAL (dev): borra los intentos del usuario, de un paso ([pasoId]) o
  /// de todos. Como la mejor marca se deriva de HISTORY, eso la deja en 0.
  /// Devuelve cuántos intentos se borraron.
  ///
  /// Local-first igual que [save]: el borrado se aplica a la cache al instante
  /// (catálogo y perfil se refrescan sin red) y se sincroniza al reconectar.
  Future<int> deleteAttempts({required String uid, String? pasoId}) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(AppConstants.historyCollection)
        .where('uid', isEqualTo: uid);
    if (pasoId != null) query = query.where('pasoId', isEqualTo: pasoId);
    final snap = await query.get();
    if (snap.docs.isEmpty) return 0;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    unawaitedWrite(batch.commit());
    return snap.docs.length;
  }

  /// Dispara la escritura sin bloquear el flujo; los errores de sync quedan
  /// registrados por el SDK y no afectan la UX del intento.
  static void unawaitedWrite(Future<void> future) {
    future.ignore();
  }
}
