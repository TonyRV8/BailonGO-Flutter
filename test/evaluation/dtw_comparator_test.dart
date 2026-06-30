import 'dart:math' as math;

import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
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
      // Offset grande en todos los componentes: aleja el costo del noise floor.
      final bad = makeSeq(30, offset: 40);
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
      // El usuario difiere fuerte solo en la feature 0 (ángulo rodilla izq).
      for (final fr in user) {
        fr[0] += 60;
      }
      final uniform = DtwComparator.compare(user, ref);
      final ignore0 = DtwComparator.compare(
        user,
        ref,
        weights: [0, ...List.filled(14, 1.0)],
      );
      expect(ignore0.alignmentScore, greaterThan(uniform.alignmentScore));
    });
  });
}
