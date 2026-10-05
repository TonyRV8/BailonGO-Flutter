import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Congela la calibración (§7-sexies). No mide scores —eso lo hace
/// `tool/bench_real.dart` con las tomas, que no se versionan— sino que protege
/// las invariantes que hacen que esos scores sigan siendo válidos.
void main() {
  group('parámetros por paso', () {
    test('los 9 pasos reales tienen calibración propia', () {
      for (final id in kRealStepIds) {
        expect(calibratedStepIds, contains(id), reason: id);
      }
      expect(calibratedStepIds.length, kRealStepIds.length);
    });

    test('un paso sin calibrar cae a los defaults', () {
      expect(paramsFor('paso_prueba').alignMax, DtwParams.defaults.alignMax);
    });

    test('solo la curva de alineación cambia por paso, y dentro de límites',
        () {
      const d = DtwParams.defaults;
      for (final id in kRealStepIds) {
        final p = paramsFor(id);
        // Acotado para que ningún paso quede indefendible: la toma regular
        // de la profesora cuesta ~0.9, así que el suelo tiene que quedar por
        // debajo (curva, no meseta) y el tramo suelo→techo no puede ser un
        // acantilado (§7-sexies).
        expect(p.alignMax, inInclusiveRange(1.0, 2.2), reason: id);
        expect(p.alignNoiseFloor, inInclusiveRange(0.05, 0.7), reason: id);
        expect(p.alignMax, greaterThanOrEqualTo(p.alignNoiseFloor + 0.4), reason: id);
        expect(p.alignCurvePower, d.alignCurvePower, reason: id);
        expect(p.coverageZeroRatio, d.coverageZeroRatio, reason: id);
        expect(p.rhythmCorrFull, d.rhythmCorrFull, reason: id);
      }
    });

    test('los pesos RNF-06 no se tocaron al calibrar', () {
      for (final id in kRealStepIds) {
        expect(paramsFor(id).alignWeight, 0.6, reason: id);
        expect(paramsFor(id).rhythmWeight, 0.4, reason: id);
      }
    });

    test('rangos y temblor cubren todas las features', () {
      expect(DtwParams.defaultFeatureRanges.length, FeatureExtractor.featureCount);
      expect(DtwParams.defaultFeatureNoise.length, FeatureExtractor.featureCount);
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

  group('ajuste por grupo de características', () {
    test('los grupos parten el vector completo, sin huecos ni solapes', () {
      final cubiertos = <int>[];
      for (final g in kFeatureGroups.values) {
        cubiertos.addAll(g);
      }
      cubiertos.sort();
      expect(cubiertos,
          List<int>.generate(FeatureExtractor.featureCount, (i) => i));
    });

    test('cada grupo tiene multiplicador y es positivo o cero', () {
      for (final g in kFeatureGroups.keys) {
        expect(kGroupScale[g], isNotNull, reason: g);
        expect(kGroupScale[g], greaterThanOrEqualTo(0), reason: g);
      }
      expect(kGroupScale.length, kFeatureGroups.length);
    });

    test('los pesos efectivos salen del vector del paso por su grupo', () {
      for (final id in kRealStepIds) {
        final base = kStepWeights[id]!;
        final eff = weightsForStep(id);
        expect(eff.length, FeatureExtractor.featureCount, reason: id);
        for (final e in kFeatureGroups.entries) {
          for (final i in e.value) {
            expect(eff[i], closeTo(base[i] * kGroupScale[e.key]!, 1e-9),
                reason: '$id[$i]');
          }
        }
      }
    });

    test('un paso sin pesos propios devuelve lista vacía', () {
      expect(weightsForStep('paso_prueba'), isEmpty);
    });

    test('algún grupo sigue pesando: no se anula la evaluación entera', () {
      for (final id in kRealStepIds) {
        expect(weightsForStep(id).reduce((a, b) => a + b), greaterThan(0),
            reason: id);
      }
    });
  });
}
