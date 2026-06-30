import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_constants.dart';
import '../engine/dtw_result.dart';

/// Persiste los intentos en la colección HISTORY (doc 5.3.3). La mejor marca
/// (RN-04) se deriva como el máximo de `scores.total` por paso, así que basta
/// con guardar cada intento.
class AttemptRepository {
  AttemptRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> save({
    required String uid,
    required String pasoId,
    required DtwResult result,
  }) async {
    await _firestore.collection(AppConstants.historyCollection).add({
      'uid': uid,
      'pasoId': pasoId,
      'scores': {
        'ritmo': result.rhythmScore.toDouble(),
        'alineacion': result.alignmentScore.toDouble(),
        'total': result.score.toDouble(),
      },
      'deviceInfo': <String, dynamic>{},
      'timestamp': FieldValue.serverTimestamp(),
      'synced': true,
    });
  }
}
