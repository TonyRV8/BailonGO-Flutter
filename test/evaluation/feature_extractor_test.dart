import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construye 33 landmarks con una pose de pie plausible. `conf` aplica a todos.
List<PoseLandmark> standingPose({double conf = 1.0}) {
  PoseLandmark p(int type, double x, double y) =>
      PoseLandmark(type: type, x: x, y: y, z: 0, confidence: conf);

  final list = List<PoseLandmark>.generate(
    33,
    (i) => p(i, 0.5, 0.5),
  );
  // Tren superior (coordenadas tipo imagen, y crece hacia abajo).
  list[11] = p(11, 0.42, 0.30); // left shoulder
  list[12] = p(12, 0.58, 0.30); // right shoulder
  list[13] = p(13, 0.38, 0.42); // left elbow
  list[14] = p(14, 0.62, 0.42); // right elbow
  list[15] = p(15, 0.36, 0.54); // left wrist
  list[16] = p(16, 0.64, 0.54); // right wrist
  // Tren inferior.
  list[23] = p(23, 0.45, 0.50); // left hip
  list[24] = p(24, 0.55, 0.50); // right hip
  list[25] = p(25, 0.45, 0.70); // left knee
  list[26] = p(26, 0.55, 0.70); // right knee
  list[27] = p(27, 0.45, 0.90); // left ankle
  list[28] = p(28, 0.55, 0.90); // right ankle
  list[29] = p(29, 0.45, 0.92); // left heel
  list[30] = p(30, 0.55, 0.92); // right heel
  list[31] = p(31, 0.48, 0.92); // left foot index
  list[32] = p(32, 0.58, 0.92); // right foot index
  return list;
}

void main() {
  group('FeatureExtractor', () {
    test('extrae vector de 22 features', () {
      final f = FeatureExtractor.extractFeatures(standingPose());
      expect(f, isNotNull);
      expect(f!.length, FeatureExtractor.featureCount);
    });

    test('null si faltan landmarks', () {
      final f = FeatureExtractor.extractFeatures(standingPose().sublist(0, 20));
      expect(f, isNull);
    });

    test('null si la visibilidad crítica es baja', () {
      final f = FeatureExtractor.extractFeatures(standingPose(conf: 0.2));
      expect(f, isNull);
    });

    test('mirrorFeatures es involutivo: mirror(mirror(f)) == f', () {
      final f = FeatureExtractor.extractFeatures(standingPose())!;
      final mm = FeatureExtractor.mirrorFeatures(
        FeatureExtractor.mirrorFeatures(f),
      );
      for (var i = 0; i < f.length; i++) {
        expect(mm[i], closeTo(f[i], 1e-9), reason: 'componente $i');
      }
    });

    test('isMirrored=true equivale a mirrorFeatures(raw)', () {
      final raw = FeatureExtractor.extractFeatures(standingPose())!;
      final mirrored =
          FeatureExtractor.extractFeatures(standingPose(), isMirrored: true)!;
      final expected = FeatureExtractor.mirrorFeatures(raw);
      for (var i = 0; i < raw.length; i++) {
        expect(mirrored[i], closeTo(expected[i], 1e-9));
      }
    });
  });
}
