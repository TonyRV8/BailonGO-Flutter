import 'dart:math' as math;

import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Genera una secuencia determinista de vectores de 15 features con movimiento
/// (oscilación senoidal por componente), opcionalmente desfasada y con offset.
List<List<double>> makeSeq(
  int len, {
  double offset = 0,
  double phase = 0,
}) {
  // Amplitudes dentro de rangos razonables por componente.
  const amp = [
    30.0, 30.0, 0.4, 0.4, 0.8, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.4, 0.4, 0.2, 0.2,
  ];
  const base = [
    150.0, 150.0, 0.9, 0.9, 1.2, 0.9, 0.9, 0.3, -0.3, 0.2, -0.2, 0.1, -0.1, 0.05,
    0.05,
  ];
  return List.generate(len, (i) {
    final t = (i / len) * 2 * math.pi + phase;
    return List<double>.generate(
      15,
      (c) => base[c] + amp[c] * math.sin(t + c * 0.3) + offset,
    );
  });
}

void main() {
  group('DtwComparator', () {
    test('secuencias idénticas -> 100 en todo', () {
      final ref = makeSeq(30);
      final r = DtwComparator.compare(ref, ref);
      expect(r.score, 100);
      expect(r.alignmentScore, 100);
      expect(r.rhythmScore, 100);
      expect(r.normalizedCost, lessThan(1e-6));
      expect(r.segmentScore, [100, 100, 100]);
      for (final t in r.segmentTempo) {
        expect(t.abs(), lessThan(0.02));
      }
    });

    test('usuario adelantado -> tempo señado positivo', () {
      final ref = makeSeq(40);
      // El usuario ejecuta en cada frame la pose que en la referencia llega
      // después (fase adelantada) -> el path se desvía hacia j > idealJ.
      final ahead = makeSeq(40, phase: 0.9);
      final r = DtwComparator.compare(ahead, ref);
      final meanTempo =
          r.segmentTempo.reduce((a, b) => a + b) / r.segmentTempo.length;
      expect(meanTempo, greaterThan(0));
    });

    test('desglose por segmento: dimensiones y consistencia', () {
      final ref = makeSeq(40);
      final user = makeSeq(40, offset: 8, phase: 0.3);
      final r = DtwComparator.compare(user, ref);
      expect(r.segmentScore.length, 3);
      expect(r.segmentTempo.length, 3);
      expect(r.segmentComponentErrors.length, 3);
      expect(r.segmentSignedErrors.length, 3);
      for (var s = 0; s < 3; s++) {
        expect(r.segmentComponentErrors[s].length, 15);
        expect(r.segmentSignedErrors[s].length, 15);
        // Precisión del segmento = RNF-06 sobre los scores del segmento.
        final expected =
            (0.6 * r.segmentAlignment[s] + 0.4 * r.segmentRhythm[s]).toInt();
        expect(r.segmentScore[s], expected);
      }
    });

    test('offset positivo -> diferencia señada positiva por componente', () {
      final ref = makeSeq(30);
      final user = makeSeq(30, offset: 10);
      final r = DtwComparator.compare(user, ref);
      // Todas las features del usuario están por encima de la referencia.
      for (var s = 0; s < 3; s++) {
        expect(r.segmentSignedErrors[s][0], greaterThan(0));
      }
    });

    test('determinismo: misma entrada -> misma salida', () {
      final ref = makeSeq(40);
      final user = makeSeq(40, offset: 5, phase: 0.2);
      final a = DtwComparator.compare(user, ref);
      final b = DtwComparator.compare(user, ref);
      expect(a.score, b.score);
      expect(a.alignmentScore, b.alignmentScore);
      expect(a.rhythmScore, b.rhythmScore);
      expect(a.worstComponentIndex, b.worstComponentIndex);
    });

    test('ejecución muy distinta -> score bajo', () {
      final ref = makeSeq(30);
      // Movimiento en contrafase: cada feature sube cuando la del modelo baja.
      // (Un offset constante ya no basta: es postura, y el motor v2 compara
      // sobre todo el movimiento; ver cabecera de DtwComparator.)
      final bad = makeSeq(30, phase: math.pi);
      final r = DtwComparator.compare(bad, ref);
      expect(r.alignmentScore, lessThan(40));
      expect(r.score, lessThan(60));
    });

    test('monotonía: más desviación -> score no mayor', () {
      final ref = makeSeq(30);
      final mild = DtwComparator.compare(makeSeq(30, offset: 5), ref);
      final harsh = DtwComparator.compare(makeSeq(30, offset: 20), ref);
      expect(harsh.alignmentScore, lessThanOrEqualTo(mild.alignmentScore));
    });

    test('ejecución especular penaliza alineación', () {
      final ref = makeSeq(30);
      final identity = DtwComparator.compare(ref, ref);
      // Usuario = referencia espejada por frame (lateralidad invertida).
      final mirrored =
          ref.map((f) => FeatureExtractor.mirrorFeatures(f)).toList();
      final r = DtwComparator.compare(mirrored, ref);
      expect(r.alignmentScore, lessThan(identity.alignmentScore));
    });

    test('entrada vacía -> resultado cero seguro', () {
      final r = DtwComparator.compare([], makeSeq(10));
      expect(r.score, 0);
      expect(r.componentErrors, isEmpty);
      expect(r.segmentAlignment, [0, 0, 0]);
      expect(r.segmentScore, [0, 0, 0]);
      expect(r.segmentTempo, [0, 0, 0]);
    });

    test('worstComponentIndex válido en rango', () {
      final ref = makeSeq(30);
      final user = makeSeq(30, offset: 10);
      final r = DtwComparator.compare(user, ref);
      expect(r.worstComponentIndex, inInclusiveRange(0, 14));
      expect(r.componentErrors.length, 15);
    });

    test('pesos: ignorar la feature que difiere sube la alineación', () {
      final ref = makeSeq(30);
      final user = makeSeq(30);
      // El usuario difiere fuerte solo en la feature 0 (ángulo rodilla izq):
      // la mueve a otro ritmo, no solo desplazada (un desplazamiento
      // constante es postura, y el motor compara sobre todo movimiento).
      for (var i = 0; i < user.length; i++) {
        user[i][0] += 60 * math.sin(i * 1.7);
      }
      // Sin zona muerta: una sola feature de 15 no debe quedar absorbida.
      final strict = DtwParams.defaults.copyWith(alignNoiseFloor: 0);
      final uniform = DtwComparator.compare(user, ref, params: strict);
      final ignore0 = DtwComparator.compare(
        user,
        ref,
        weights: [0, ...List.filled(14, 1.0)],
        params: strict,
      );
      expect(ignore0.alignmentScore, greaterThan(uniform.alignmentScore));
    });
  });
}
