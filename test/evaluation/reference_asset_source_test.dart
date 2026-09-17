import 'dart:convert';

import 'package:bailongo/features/evaluation/data/reference_asset_source.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const indices = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];
  // Pose de pie en coordenadas x, y (diezmilésimas) + visibilidad (centésimas).
  const pose = {
    11: [4200, 3000], 12: [5800, 3000], 13: [3800, 4200], 14: [6200, 4200],
    15: [3600, 5400], 16: [6400, 5400], 23: [4500, 5000], 24: [5500, 5000],
    25: [4500, 7000], 26: [5500, 7000], 27: [4500, 9000], 28: [5500, 9000],
    29: [4500, 9200], 30: [5500, 9200], 31: [4800, 9200], 32: [5800, 9200],
  };

  String doc({int format = 1}) => jsonEncode({
        'format': format,
        'pasoId': 'x',
        'aspect': 1280 / 720,
        'stepMs': 33,
        'indices': indices,
        'frames': [
          for (var k = 0; k < 3; k++)
            [for (final i in indices) ...[...pose[i]!, 100]],
        ],
      });

  test('reconstruye las features de cada fotograma', () {
    final frames = ReferenceAssetSource.parse(doc())!;
    expect(frames.length, 3);
    expect(frames.first.length, FeatureExtractor.featureCount);
  });

  test('ignora un formato desconocido', () {
    expect(ReferenceAssetSource.parse(doc(format: 99)), isNull);
  });
}
