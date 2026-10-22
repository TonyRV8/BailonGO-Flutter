/// Califica UNA toma suelta contra la referencia de su paso, con el mismo
/// pipeline que la app (features con aspecto, rejilla de 33 ms, ventana =
/// duración de la referencia, pesos y umbrales del paso).
///
/// Sirve para comprobar fuera del teléfono qué nota daría una grabación, sin
/// el desfase entre el reloj de la captura y el de la pantalla que se filma.
///
/// Uso:
///   python tool/extract_landmarks.py salida.json mi_video.mp4
///   dart run tool/score_take.dart salida.json <clave> <pasoId>
library;

import 'dart:convert';
import 'dart:io';

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/frame_resampler.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';

import 'bench_real.dart' show Take, featuresOf, loadTakes, toLandmarks;

/// Features de [t] llevadas a la rejilla de [targetMs] estirando el tiempo:
/// la toma completa cabe en la ventana aunque dure más o menos.
List<List<double>> stretchedFeatures(Take t,
    {required int targetMs, bool mirror = false}) {
  final feats = <List<double>>[];
  final times = <int>[];
  final factor = targetMs / t.durationMs;
  for (var i = 0; i < t.frames.length; i++) {
    final v = FeatureExtractor.extractFeatures(toLandmarks(t.frames[i]),
        aspectRatio: t.aspect, isMirrored: mirror);
    if (v != null) {
      feats.add(v);
      times.add((i * 33 * factor).round());
    }
  }
  return FrameResampler.toGrid(feats, times, durationMs: targetMs);
}

void main(List<String> args) {
  if (args.length < 3) {
    stdout.writeln('uso: dart run tool/score_take.dart <json> <clave> <pasoId>');
    exit(64);
  }
  final takes = loadTakes(args[0]);
  final take = takes[args[1]];
  if (take == null) {
    stdout.writeln('clave no encontrada. Disponibles: ${takes.keys.join(', ')}');
    exit(1);
  }
  final stepId = args[2];

  final rawProf =
      jsonDecode(File('tool/landmarks.json').readAsStringSync())
          as Map<String, dynamic>;
  final e = rawProf[stepId] as Map<String, dynamic>?;
  if (e == null) {
    stdout.writeln('paso desconocido: $stepId');
    exit(1);
  }
  final profTake = Take(
    stepId,
    [
      for (final f in e['frames'] as List)
        (f as List).map((x) => (x as num).toDouble()).toList(growable: false),
    ],
    ((e['height'] as num?) ?? 1280) / ((e['width'] as num?) ?? 720),
  );

  final ref = featuresOf(profTake, durationMs: profTake.durationMs.round());
  // `espejo`: la toma viene volteada horizontalmente (p. ej. grabada con
  // la cámara frontal, que guarda el video en espejo).
  final mirror = args.contains('espejo');
  // `estirar`: la toma entera se lleva a la ventana de la referencia en vez de
  // cortarse al final. Sirve para separar la FORMA del tempo de la grabación
  // cuando la toma no se bailó con la música del paso.
  final stretch = args.contains('estirar');
  // `completo`: se evalúa la toma ENTERA aunque dure más que la referencia,
  // en vez de cortarla al cerrarse la ventana. El DTW y la correlación de
  // ritmo ya comparan secuencias de distinta longitud.
  final full = args.contains('completo');
  final user = stretch
      ? stretchedFeatures(take, targetMs: ref.length * 33, mirror: mirror)
      : featuresOf(take,
          durationMs: full ? take.durationMs.round() : ref.length * 33,
          mirror: mirror);
  final r = DtwComparator.compare(user, ref,
      weights: weightsForStep(stepId), params: paramsFor(stepId));

  final p = paramsFor(stepId);
  stdout.writeln('toma      ${take.key}  '
      '(${take.frames.length} fotogramas, ${(take.durationMs / 1000).toStringAsFixed(1)} s)');
  stdout.writeln('paso      $stepId  '
      '(referencia ${ref.length} fotogramas, '
      '${(ref.length * 33 / 1000).toStringAsFixed(1)} s)');
  stdout.writeln('espejo    ${mirror ? 'sí (toma volteada)' : 'no'}'
      '${stretch ? '   · ventana estirada (sin cortar el final)' : ''}');
  stdout.writeln('umbrales  floor ${p.alignNoiseFloor.toStringAsFixed(3)}  '
      'max ${p.alignMax.toStringAsFixed(3)}');
  stdout.writeln('');
  stdout.writeln('TOTAL        ${r.score}');
  stdout.writeln('alineación   ${r.alignmentScore}   '
      'tramos ${r.segmentAlignment.join(' · ')}');
  stdout.writeln('ritmo        ${r.rhythmScore}   '
      'tramos ${r.segmentRhythm.join(' · ')}');
  stdout.writeln('tramos total ${r.segmentScore.join(' · ')}');
  stdout.writeln('');
  stdout.writeln('costo relativo ${r.relativeCost.toStringAsFixed(3)}  '
      '(0 = idéntico, 1 = tan lejos como quedarse quieto)');
  stdout.writeln('desvío del camino ${r.pathDeviation.toStringAsFixed(3)}  '
      '· espejo ${r.mirrorFactor.toStringAsFixed(2)}');

  // Con `grupos`: de dónde sale la diferencia. Se repite la comparación
  // dejando vivo un solo grupo de características cada vez, así el costo
  // relativo de cada fila es el que aportaría esa parte del cuerpo sola.
  if (args.contains('grupos')) {
    stdout.writeln('');
    stdout.writeln('costo relativo por grupo '
        '(solo esas características):');
    final base = weightsForStep(stepId);
    final rows = <({String g, double cost, int score})>[];
    for (final entry in kFeatureGroups.entries) {
      final w = List<double>.filled(base.length, 0);
      var any = false;
      for (final i in entry.value) {
        w[i] = base[i];
        if (base[i] > 0) any = true;
      }
      if (!any) continue;
      final g = DtwComparator.compare(user, ref,
          weights: w, params: paramsFor(stepId));
      rows.add((g: entry.key, cost: g.relativeCost, score: g.alignmentScore));
    }
    rows.sort((a, b) => b.cost.compareTo(a.cost));
    for (final row in rows) {
      stdout.writeln('  ${row.g.padRight(12)}'
          '${row.cost.toStringAsFixed(3).padLeft(7)}   '
          'alineación ${row.score}');
    }
  }
}
