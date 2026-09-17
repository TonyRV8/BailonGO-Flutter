import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_constants.dart';
import '../engine/feature_extractor.dart';

/// Lee/escribe los frames de referencia en la colección REFERENCE_DATA
/// (doc 5.3.3). Firestore no soporta arreglos anidados, así que las features se
/// guardan aplanadas (`flat` = frameCount × featureSize) y se reconstruyen al
/// cargar.
class ReferenceRemoteDataSource {
  ReferenceRemoteDataSource({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String pasoId) =>
      _firestore.collection(AppConstants.referenceDataCollection).doc(pasoId);

  /// Carga los frames de referencia; `null` si el documento no existe o se
  /// generó con otra versión del extractor (features distintas a las que
  /// produce hoy la captura en vivo: compararlas daría notas sin sentido).
  Future<List<List<double>>?> load(String pasoId) async {
    try {
      final snap = await _doc(pasoId).get();
      if (!snap.exists) return null;
      final data = snap.data()!;
      final featureSize = (data['featureSize'] as num?)?.toInt() ?? 0;
      final version = (data['extractorVersion'] as num?)?.toInt() ?? 1;
      if (version != FeatureExtractor.version ||
          featureSize != FeatureExtractor.featureCount) {
        return null;
      }
      final flat = (data['flat'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
      if (flat == null || featureSize <= 0) return null;

      final frames = <List<double>>[];
      for (var i = 0; i + featureSize <= flat.length; i += featureSize) {
        frames.add(flat.sublist(i, i + featureSize));
      }
      return frames;
    } catch (_) {
      return null; // sin red/índice: el repo cae al asset.
    }
  }

  /// Guarda los frames de referencia (uso dev). Requiere abrir temporalmente la
  /// regla de escritura de `reference_data`.
  Future<void> save(String pasoId, List<List<double>> frames) async {
    final featureSize = frames.isEmpty ? 0 : frames.first.length;
    final flat = <double>[for (final f in frames) ...f];
    await _doc(pasoId).set({
      'pasoId': pasoId,
      'frameCount': frames.length,
      'featureSize': featureSize,
      'extractorVersion': FeatureExtractor.version,
      'fps': 30,
      'flat': flat,
    });
  }
}
