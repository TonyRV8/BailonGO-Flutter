import 'dart:convert';

import 'package:flutter/services.dart';

import '../../pose/domain/entities/pose_landmark.dart';
import '../engine/feature_extractor.dart';

/// Referencia empaquetada como asset: landmarks de la toma ideal muestreados
/// cada 33 ms (`assets/references/<pasoId>.json`, generados con
/// `tool/build_references.py`).
///
/// Se guardan LANDMARKS y no features: las features se calculan aquí con el
/// extractor vigente, así que un cambio en [FeatureExtractor] nunca deja la
/// referencia desfasada respecto a la captura en vivo (lo que sí pasaba con
/// las features guardadas en Firestore).
class ReferenceAssetSource {
  static const int formatVersion = 1;

  /// Features de la referencia; `null` si el paso no tiene asset.
  Future<List<List<double>>?> load(String pasoId) async {
    final String raw;
    try {
      raw = await rootBundle.loadString('assets/references/$pasoId.json');
    } catch (_) {
      return null;
    }
    return parse(raw);
  }

  /// Separado de [load] para poder probarlo sin bundle.
  static List<List<double>>? parse(String raw) {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    if ((doc['format'] as num?)?.toInt() != formatVersion) return null;
    final aspect = (doc['aspect'] as num).toDouble();
    final indices =
        (doc['indices'] as List).map((e) => (e as num).toInt()).toList();

    final out = <List<double>>[];
    for (final row in doc['frames'] as List) {
      final values = row as List;
      if (values.length < indices.length * 3) continue;
      final byIndex = <int, PoseLandmark>{};
      for (var k = 0; k < indices.length; k++) {
        final i = indices[k];
        byIndex[i] = PoseLandmark(
          type: i,
          x: (values[k * 3] as num) / 10000,
          y: (values[k * 3 + 1] as num) / 10000,
          z: 0,
          confidence: (values[k * 3 + 2] as num) / 100,
        );
      }
      // El extractor espera los 33; los que no se guardaron no los usa.
      final landmarks = List<PoseLandmark>.generate(
        33,
        (i) =>
            byIndex[i] ??
            PoseLandmark(type: i, x: 0, y: 0, z: 0, confidence: 0),
      );
      final f = FeatureExtractor.extractFeatures(landmarks, aspectRatio: aspect);
      if (f != null) out.add(f);
    }
    return out;
  }
}
