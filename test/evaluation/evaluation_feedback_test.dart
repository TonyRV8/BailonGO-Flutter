import 'package:bailongo/features/evaluation/domain/evaluation_feedback.dart';
import 'package:bailongo/features/evaluation/engine/dtw_result.dart';
import 'package:flutter_test/flutter_test.dart';

DtwResult makeResult({
  List<int> segAlign = const [90, 90, 90],
  List<int> segRhythm = const [90, 90, 90],
  List<double> segTempo = const [0, 0, 0],
  List<List<double>> segErrors = const [[], [], []],
  List<List<double>> segSigned = const [[], [], []],
}) {
  return DtwResult(
    score: 80,
    rhythmScore: 90,
    alignmentScore: 90,
    normalizedCost: 0.1,
    segmentRhythm: segRhythm,
    segmentAlignment: segAlign,
    segmentScore: const [80, 80, 80],
    segmentTempo: segTempo,
    segmentComponentErrors: segErrors,
    segmentSignedErrors: segSigned,
    componentErrors: const [],
    worstComponentIndex: 0,
  );
}

List<double> zeros() => List<double>.filled(22, 0);

void main() {
  group('buildFeedback', () {
    test('3 segmentos con etiquetas Inicio/Medio/Final', () {
      final f = buildFeedback(makeResult());
      expect(f.segments.length, 3);
      expect(f.segments.map((s) => s.label), ['Inicio', 'Medio', 'Final']);
    });

    test('segmento bien alineado y a ritmo -> sin consejos', () {
      final f = buildFeedback(makeResult());
      for (final s in f.segments) {
        expect(s.tips, isEmpty);
      }
    });

    test('pie bajo (signed positivo en altura de tobillo) -> "levanta más"',
        () {
      final errors = zeros()..[5] = 0.2;
      final signed = zeros()..[5] = 0.1;
      final f = buildFeedback(makeResult(
        segAlign: const [50, 90, 90],
        segErrors: [errors, zeros(), zeros()],
        segSigned: [signed, zeros(), zeros()],
      ));
      expect(f.segments[0].tips.first, contains('Levanta más el pie izquierdo'));
      expect(f.segments[1].tips, isEmpty);
    });

    test('rodilla muy estirada (signed negativo en ángulo) -> "estira" inverso',
        () {
      final errors = zeros()..[1] = 0.3;
      final signed = zeros()..[1] = -0.1;
      final f = buildFeedback(makeResult(
        segAlign: const [90, 90, 40],
        segErrors: [zeros(), zeros(), errors],
        segSigned: [zeros(), zeros(), signed],
      ));
      expect(
          f.segments[2].tips.first, contains('Estira un poco más la rodilla'));
    });

    test('tempo adelantado -> "ve más lento"; atrasado -> "ve más rápido"', () {
      final f = buildFeedback(makeResult(segTempo: const [0.1, -0.1, 0.0]));
      expect(f.segments[0].tips.single, contains('más lento'));
      expect(f.segments[1].tips.single, contains('más rápido'));
      expect(f.segments[2].tips, isEmpty);
    });

    test('ritmo bajo sin dirección -> consejo de constancia', () {
      final f = buildFeedback(makeResult(segRhythm: const [50, 90, 90]));
      expect(f.segments[0].tips.single, contains('constante'));
    });

    test('error alto sin dirección estable -> consejo neutro "Revisa"', () {
      final errors = zeros()..[4] = 0.3;
      final f = buildFeedback(makeResult(
        segAlign: const [50, 90, 90],
        segErrors: [errors, zeros(), zeros()],
        segSigned: [zeros(), zeros(), zeros()],
      ));
      expect(f.segments[0].tips.first, startsWith('Revisa'));
    });

    test('feature con peso 0 (error 0) nunca genera consejo', () {
      // Solo la feature 15 tiene error; el resto en 0 -> un solo consejo útil.
      final errors = zeros()..[15] = 0.25;
      final signed = zeros()..[15] = -0.1;
      final f = buildFeedback(makeResult(
        segAlign: const [40, 90, 90],
        segErrors: [errors, zeros(), zeros()],
        segSigned: [signed, zeros(), zeros()],
      ));
      expect(f.segments[0].tips.length, 1);
      expect(f.segments[0].tips.first, contains('brazo izquierdo'));
    });
  });
}
