import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Congela la calibración por paso (§7-ter). No mide scores —eso lo hace
/// `tool/calibrate.dart` con los videos, que no se versionan— sino que protege
/// las invariantes que hacen que esos scores sigan siendo válidos.
void main() {
  group('parámetros calibrados por paso', () {
    test('los 9 pasos reales tienen calibración propia', () {
      for (final id in kRealStepIds) {
        expect(calibratedStepIds, contains(id),
            reason: '$id se quedó sin calibrar: volvería a los defaults '
                'globales, que dejan 4 de 9 pasos fuera de banda');
      }
      expect(calibratedStepIds.length, kRealStepIds.length);
    });

    test('un paso sin calibrar cae a los defaults', () {
      expect(paramsFor('paso_prueba').alignMax, DtwParams.defaults.alignMax);
      expect(paramsFor('no_existe').alignNoiseFloor,
          DtwParams.defaults.alignNoiseFloor);
    });

    test('cada paso tiene una curva de puntuación válida', () {
      for (final id in kRealStepIds) {
        final p = paramsFor(id);
        // Sin esto `_costToAlignScore` divide por cero o invierte la curva.
        expect(p.alignMax, greaterThan(p.alignNoiseFloor), reason: id);
        expect(p.alignNoiseFloor, greaterThanOrEqualTo(0), reason: id);
        expect(p.alignCurvePower, greaterThan(0), reason: id);
      }
    });

    test('los pesos RNF-06 no se tocaron al calibrar', () {
      for (final id in kRealStepIds) {
        expect(paramsFor(id).alignWeight, 0.6, reason: id);
        expect(paramsFor(id).rhythmWeight, 0.4, reason: id);
      }
    });

    test('los rangos por feature cubren todas las features', () {
      expect(DtwParams.defaultFeatureRanges.length, FeatureExtractor.featureCount);
      for (final r in DtwParams.defaultFeatureRanges) {
        expect(r, greaterThan(0));
      }
    });

    test('cada paso real pondera todas las features', () {
      for (final id in kRealStepIds) {
        expect(kStepWeights[id], isNotNull, reason: id);
        expect(kStepWeights[id]!.length, FeatureExtractor.featureCount, reason: id);
      }
    });
  });
}
