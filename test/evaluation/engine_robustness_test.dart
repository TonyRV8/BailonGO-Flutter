import 'dart:math' as math;

import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/frame_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Casos que la versión portada del motor evaluaba al revés en uso real
/// (implementar_pasos.txt §7-quater). La calibración fina vive en
/// `tool/bench.dart` con las tomas reales; aquí se congelan las propiedades.

/// Paso sintético de [seconds] s a 30 fps: 26 features que oscilan con
/// amplitud cómoda frente al rango y al temblor de cada una.
List<List<double>> dance(double seconds,
    {double phase = 0, double bias = 0, double speed = 1}) {
  final n = (seconds * 30).round();
  const ranges = DtwParams.defaultFeatureRanges;
  return List.generate(n, (i) {
    final t = i / 30.0 * speed;
    return List<double>.generate(26, (c) {
      // Distinta frecuencia por feature para que haya "acentos".
      final f = 0.6 + (c % 5) * 0.25;
      return ranges[c] * (0.08 * math.sin(2 * math.pi * f * t + phase + c) +
          bias);
    });
  });
}

/// Temblor gaussiano del detector, proporcional al rango de cada feature.
List<List<double>> withJitter(List<List<double>> seq, double frac, int seed) {
  final rng = math.Random(seed);
  const ranges = DtwParams.defaultFeatureRanges;
  double g() {
    final u1 = rng.nextDouble().clamp(1e-12, 1.0);
    return math.sqrt(-2 * math.log(u1)) *
        math.cos(2 * math.pi * rng.nextDouble());
  }

  return [
    for (final f in seq)
      List<double>.generate(f.length, (c) => f[c] + ranges[c] * frac * g()),
  ];
}

void main() {
  final ref = dance(12);

  test('buena ejecución con temblor y otra complexión -> nota alta', () {
    // `bias` desplaza la postura media (otra persona, otra cámara).
    final user = withJitter(dance(12, bias: 0.03), 0.01, 1);
    final r = DtwComparator.compare(user, ref);
    expect(r.score, greaterThanOrEqualTo(85));
  });

  test('quedarse quieto -> nota casi nula', () {
    final still = withJitter(List.generate(ref.length, (_) => ref.first), 0.01, 2);
    final r = DtwComparator.compare(still, ref);
    expect(r.score, lessThanOrEqualTo(10));
    expect(r.coverage, lessThan(0.3));
  });

  test('pararse a la mitad -> claramente peor que completar el paso', () {
    final full = withJitter(ref, 0.01, 3);
    final half = [
      for (var i = 0; i < ref.length; i++) ref[math.min(i, ref.length ~/ 2)],
    ];
    final rFull = DtwComparator.compare(full, ref);
    final rHalf = DtwComparator.compare(withJitter(half, 0.01, 3), ref);
    expect(rHalf.score, lessThanOrEqualTo(60));
    expect(rFull.score - rHalf.score, greaterThanOrEqualTo(30));
    // El tramo final (quieto) debe verse vacío en el desglose.
    expect(rHalf.segmentScore[2], lessThan(20));
  });

  test('ir a destiempo baja el ritmo', () {
    final onBeat = DtwComparator.compare(withJitter(ref, 0.01, 4), ref);
    // Mismos movimientos a otro tempo (35 % más rápido que la música).
    final offBeat =
        DtwComparator.compare(withJitter(dance(12, speed: 1.35), 0.01, 4), ref);
    expect(offBeat.rhythmScore, lessThan(onBeat.rhythmScore));
    expect(offBeat.score, lessThan(onBeat.score));
  });

  test('un teléfono lento (15 fps irregulares) no castiga una buena ejecución',
      () {
    final rng = math.Random(5);
    final frames = <List<double>>[];
    final times = <int>[];
    for (var t = 0.0; t < ref.length * 33; t += 50 + rng.nextInt(40)) {
      frames.add(ref[math.min((t / 33).round(), ref.length - 1)]);
      times.add(t.round());
    }
    final grid = FrameResampler.toGrid(frames, times,
        durationMs: ref.length * FrameResampler.stepMs);
    expect(grid.length, ref.length);
    final r = DtwComparator.compare(withJitter(grid, 0.01, 5), ref);
    // La alineación no debe resentirse (el remuestreo lo absorbe). El ritmo
    // sí baja algo: la interpolación de huecos de 50-90 ms aplana los acentos
    // del perfil de velocidad y desde §7-sexies el ritmo es estricto para
    // separar bailes ajenos (correlación 0.30 → 0, 0.70 → 100).
    expect(r.alignmentScore, greaterThanOrEqualTo(95));
    expect(r.score, greaterThanOrEqualTo(80));
  });
}
