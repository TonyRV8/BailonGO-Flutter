/// Sonda: ¿cuánto gana la nota si cada paso tiene DOS referencias en vez de
/// una?
///
/// La segunda referencia es la tanda `bailes10profacalibracion` (la profesora
/// repitiendo cada paso, nota 10). Se la lleva a la rejilla de la referencia
/// original ESTIRANDO el tiempo, no cortando: las tomas nuevas duran entre un
/// 1 % y un 13 % más, y lo que interesa de ellas es la forma, no el tempo de
/// esa sesión de grabación.
///
/// Con dos referencias el costo de una toma pasa a ser el MÍNIMO contra las
/// dos: la pregunta deja de ser "¿te pareces a esta grabación?" y pasa a ser
/// "¿tu ejecución cae dentro de lo que cuenta como este paso?".
///
/// Lo que hay que mirar en la salida: que las tomas de alumno bajen de costo
/// MÁS que los bailes ajenos. Si los ajenos bajan igual, el mínimo sobre dos
/// referencias solo está aflojando el listón para todos y no sirve.
///
/// Uso: dart run tool/probe_multiref.dart
library;

import 'dart:io';

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/frame_resampler.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';

import 'bench_real.dart'
    show Take, featuresOf, folderToStep, loadLabels, loadTakes, toLandmarks;

/// Las tomas de 10 viven con el resto del corpus desde el 2026-10-21:
/// `BailesREVISADOS/<Carpeta>/Profa_<Carpeta>_calif10`.
bool esToma10(String key) => key.split('/').last.startsWith('Profa_');

/// Features de [t] llevadas a una rejilla de [targetMs] ESTIRANDO el tiempo
/// (la toma entera cabe en la ventana, aunque dure más o menos).
List<List<double>> stretched(Take t, {required int targetMs}) {
  final feats = <List<double>>[];
  final times = <int>[];
  final factor = targetMs / t.durationMs;
  for (var i = 0; i < t.frames.length; i++) {
    final v = FeatureExtractor.extractFeatures(toLandmarks(t.frames[i]),
        aspectRatio: t.aspect);
    if (v != null) {
      feats.add(v);
      times.add((i * 33 * factor).round());
    }
  }
  return FrameResampler.toGrid(feats, times, durationMs: targetMs);
}

double costOf(List<List<double>> user, List<List<double>> ref, String step) =>
    DtwComparator.compare(user, ref,
            weights: weightsForStep(step), params: paramsFor(step))
        .relativeCost;

void main() {
  final prof = loadTakes('tool/landmarks.json');
  final real = loadTakes('tool/landmarks_revisados.json');
  final labels = loadLabels('tool/labels.json');

  // Referencias por paso: la original y la tanda nueva estirada a su rejilla.
  final refA = <String, List<List<double>>>{};
  final refB = <String, List<List<double>>>{};
  for (final id in kRealStepIds) {
    final g = prof[id]!;
    refA[id] = featuresOf(g, durationMs: g.durationMs.round());
    final dur = refA[id]!.length * 33;
    final nueva = real.entries
        .firstWhere((e) => esToma10(e.key) && folderToStep[e.key.split('/').first] == id);
    refB[id] = stretched(nueva.value, targetMs: dur);
  }

  // Cuánto se parecen entre sí las dos referencias: si el costo es minúsculo,
  // la segunda no aporta variación y el mínimo no puede ganar nada.
  stdout.writeln('distancia entre las dos referencias del mismo paso');
  for (final id in kRealStepIds) {
    stdout.writeln('  ${id.padRight(24)}'
        '${costOf(refB[id]!, refA[id]!, id).toStringAsFixed(3)}');
  }

  // Grupos de tomas reales.
  final rows = <String, List<({double a, double b})>>{};
  void add(String group, double a, double b) =>
      (rows[group] ??= []).add((a: a, b: b));

  for (final e in real.entries) {
    final folder = e.key.split('/').first;
    final ids = folder == 'randoms' ? kRealStepIds : [folderToStep[folder]];
    for (final id in ids) {
      if (id == null || !refA.containsKey(id)) continue;
      final label = labels[e.key];
      if (label == null) continue;
      final dur = refA[id]!.length * 33;
      final user = featuresOf(e.value, durationMs: dur);
      add(
          folder == 'randoms'
              ? 'ajenos'
              : esToma10(e.key)
                  ? 'tomas 10'
                  : label.name,
          costOf(user, refA[id]!, id),
          costOf(user, refB[id]!, id));
    }
  }

  // La toma imperfecta de la profesora (la única que calificó ella misma).
  for (final id in kRealStepIds) {
    final reg = prof['${id}_regular']!;
    final dur = refA[id]!.length * 33;
    final user = featuresOf(reg, durationMs: dur);
    add('regular', costOf(user, refA[id]!, id), costOf(user, refB[id]!, id));
  }

  stdout.writeln('\ncosto relativo medio por grupo');
  stdout.writeln('  ${'grupo'.padRight(12)}${'n'.padLeft(4)}'
      '${'solo A'.padLeft(9)}${'solo B'.padLeft(9)}'
      '${'mín(A,B)'.padLeft(10)}${'gana'.padLeft(8)}');
  const orden = ['regular', 'tomas 10', 'avril', 'gabo', 'abdiel', 'toto',
    'otro', 'ajenos'];
  for (final g in [...orden, ...rows.keys.where((k) => !orden.contains(k))]) {
    final xs = rows[g];
    if (xs == null || xs.isEmpty) continue;
    double mean(Iterable<double> v) => v.reduce((a, b) => a + b) / xs.length;
    final a = mean(xs.map((x) => x.a));
    final b = mean(xs.map((x) => x.b));
    final m = mean(xs.map((x) => x.a < x.b ? x.a : x.b));
    stdout.writeln('  ${g.padRight(12)}${xs.length.toString().padLeft(4)}'
        '${a.toStringAsFixed(3).padLeft(9)}${b.toStringAsFixed(3).padLeft(9)}'
        '${m.toStringAsFixed(3).padLeft(10)}'
        '${(a - m).toStringAsFixed(3).padLeft(8)}');
  }
  stdout.writeln('\n"gana" = cuánto baja el costo al usar las dos referencias.'
      '\nSirve si las tomas de alumno ganan MÁS que los bailes ajenos.');
}
