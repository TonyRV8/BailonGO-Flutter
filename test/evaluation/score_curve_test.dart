import 'package:bailongo/features/evaluation/engine/score_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// La curva reparte la escala de la nota final. Lo que no puede hacer nunca es
/// cambiar el ORDEN de dos intentos ni mover los extremos: si los rompiera,
/// dejaría de ser un cambio de presentación y pasaría a ser una medición
/// distinta.
void main() {
  setUp(() => ScoreCurve.enabled = true);

  group('curva de presentación', () {
    test('deja fijos los extremos', () {
      expect(ScoreCurve.applyInt(0), 0);
      expect(ScoreCurve.applyInt(100), 100);
    });

    test('es estrictamente creciente, así que conserva el orden', () {
      var previous = -1.0;
      for (var s = 0; s <= 100; s++) {
        final v = ScoreCurve.apply(s.toDouble());
        expect(v, greaterThan(previous), reason: 'nota $s');
        previous = v;
      }
    });

    test('nunca se sale de 0-100', () {
      for (var s = -20; s <= 120; s++) {
        final v = ScoreCurve.apply(s.toDouble());
        expect(v, inInclusiveRange(0, 100), reason: 'nota $s');
      }
    });

    test('baja la zona media y sube el tramo alto', () {
      // El reparto que pidió el usuario tras probar la app. La curva actúa
      // sobre CADA componente, así que es más pronunciada que el efecto
      // final: estas bajadas de 9-13 puntos dan 5-7 en el total, porque el
      // total es la media ponderada de dos componentes que no coinciden.
      for (final s in [50, 60, 70, 76]) {
        final delta = s - ScoreCurve.apply(s.toDouble());
        expect(delta, inInclusiveRange(8, 14), reason: 'nota $s');
      }
      expect(ScoreCurve.apply(84), greaterThan(84));
      expect(ScoreCurve.apply(90), greaterThan(90));
      expect(ScoreCurve.apply(95), greaterThan(95));
    });

    test('los extremos bajos apenas se mueven', () {
      for (final s in [0, 5, 10, 20]) {
        expect((s - ScoreCurve.apply(s.toDouble())).abs(), lessThanOrEqualTo(3),
            reason: 'nota $s');
      }
    });

    test('los puntos de la tabla van en orden y dentro de rango', () {
      for (var i = 1; i < ScoreCurve.anchors.length; i++) {
        final (x0, y0) = ScoreCurve.anchors[i - 1];
        final (x1, y1) = ScoreCurve.anchors[i];
        expect(x1, greaterThan(x0));
        expect(y1, greaterThan(y0));
        expect(y1, inInclusiveRange(0, 100));
      }
    });

    test('apagada no toca nada', () {
      ScoreCurve.enabled = false;
      for (final s in [13, 42, 70, 88]) {
        expect(ScoreCurve.applyInt(s), s);
      }
      ScoreCurve.enabled = true;
    });
  });
}
