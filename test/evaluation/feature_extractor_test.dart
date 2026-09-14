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
    test('extrae el vector completo de features', () {
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

    group('features de cadera (22-25)', () {
      test('una pose simétrica y centrada no acusa inclinación ni sway', () {
        final f = FeatureExtractor.extractFeatures(standingPose())!;
        expect(f[22], closeTo(0, 1e-9), reason: 'caderas a la misma altura');
        expect(f[23], closeTo(0, 1e-9), reason: 'cadera alineada con el torso');
        expect(f[25], greaterThan(0), reason: 'ancho cadera / ancho hombros');
      });

      test('subir una cadera cambia el signo de la inclinación', () {
        final up = standingPose();
        // y crece hacia abajo: restar sube la cadera izquierda.
        up[23] = const PoseLandmark(type: 23, x: 0.45, y: 0.46, z: 0, confidence: 1);
        final f = FeatureExtractor.extractFeatures(up)!;
        expect(f[22], lessThan(0));
      });

      test('desplazar la cadera a un lado se detecta como sway', () {
        final swayed = standingPose();
        swayed[23] =
            const PoseLandmark(type: 23, x: 0.52, y: 0.50, z: 0, confidence: 1);
        swayed[24] =
            const PoseLandmark(type: 24, x: 0.62, y: 0.50, z: 0, confidence: 1);
        final f = FeatureExtractor.extractFeatures(swayed)!;
        expect(f[23], greaterThan(0.1), reason: 'cadera a la derecha del torso');
      });

      test('sin hombros visibles las features relativas quedan neutras', () {
        final noShoulders = standingPose();
        for (final i in [11, 12]) {
          noShoulders[i] =
              PoseLandmark(type: i, x: 0.5, y: 0.30, z: 0, confidence: 0.1);
        }
        final f = FeatureExtractor.extractFeatures(noShoulders)!;
        expect(f[23], 0);
        expect(f[24], 0);
        expect(f[25], 0);
        // La inclinación solo necesita las caderas, que son críticas.
        expect(f[22], closeTo(0, 1e-9));
      });

      test('el espejo invierte inclinación y sway, no altura ni giro', () {
        final f = FeatureExtractor.extractFeatures(standingPose())!;
        final tweaked = List<double>.from(f)
          ..[22] = 0.3
          ..[23] = -0.4
          ..[24] = 1.2
          ..[25] = 0.8;
        final m = FeatureExtractor.mirrorFeatures(tweaked);
        expect(m[22], -0.3);
        expect(m[23], 0.4);
        expect(m[24], 1.2);
        expect(m[25], 0.8);
      });
    });
  });
}
