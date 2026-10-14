import 'package:bailongo/features/catalog/data/catalog_seed.dart';
import 'package:bailongo/features/evaluation/domain/step_cues.dart';
import 'package:flutter_test/flutter_test.dart';

/// La pista de flechas se escribe a mano, así que lo que se comprueba es que
/// ninguna señal se salga de la ventana del intento ni se pise con la
/// siguiente: son los dos errores fáciles al editar los segundos.
void main() {
  group('pistas de flechas', () {
    test('los 9 pasos reales tienen pista', () {
      for (final step in kRealSteps) {
        expect(cuesFor(step.id), isNotEmpty, reason: step.id);
      }
    });

    test('cada señal cabe en la duración del paso', () {
      for (final step in kRealSteps) {
        final durMs = (step.duracionCicloSeg * 1000).round();
        for (final cue in cuesFor(step.id)) {
          expect(cue.tMs - kCueLeadMs, greaterThanOrEqualTo(0),
              reason: '${step.id} @ ${cue.t}');
          expect(cue.endMs, lessThanOrEqualTo(durMs),
              reason: '${step.id} @ ${cue.t}');
        }
      }
    });

    test('las señales van en orden y no se solapan', () {
      for (final step in kRealSteps) {
        final cues = cuesFor(step.id);
        for (var i = 1; i < cues.length; i++) {
          expect(cues[i].tMs, greaterThan(cues[i - 1].tMs), reason: step.id);
          expect(cues[i].tMs - kCueLeadMs,
              greaterThanOrEqualTo(cues[i - 1].endMs),
              reason: '${step.id}: la flecha ${cues[i].t} aparece antes de '
                  'que termine la de ${cues[i - 1].t}');
        }
      }
    });
  });
}
