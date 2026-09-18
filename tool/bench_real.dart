/// Banco con TOMAS REALES ETIQUETADAS (implementar_pasos.txt §7-sexies).
///
/// `bench.dart` fabricaba al alumno a partir de la propia profesora. Este banco
/// usa grabaciones de alumnos reales (BailonGObailes/BailesREVISADOS, extraídas
/// con `tool/extract_revisados.py`) con la nota que les dio la revisión humana:
///
///   ideal vs sí misma ............ 100
///   toma "regular" de la profesora  70-80   (antes se etiquetó 50; revisada)
///   alumnos (Gabo, Primo, Toto) ... 40-50
///   alumna Avril .................. alta en alineación pero < 90 → 70-85
///   randoms (otro baile) .......... muy baja, contra las 9 referencias
///
/// Cada toma se procesa EXACTAMENTE como la app procesa una captura: features
/// con corrección de aspecto, rejilla de 33 ms y ventana = duración de la
/// referencia (lo que sobra se corta; si la toma es más corta, se congela la
/// última pose, igual que FrameResampler en vivo).
///
/// Uso:
///   dart run tool/bench_real.dart                       tabla
///   dart run tool/bench_real.dart --detail              + tramos y peor feature
///   dart run tool/bench_real.dart --fit                 floor/max por paso
///   dart run tool/bench_real.dart --sweep               barrido global
///   dart run tool/bench_real.dart --global              defaults sin por-paso
///   dart run tool/bench_real.dart --mirror              alumnos espejados
///   --nf=x --max=x --pow=x --clip=x ...                 variantes
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/dtw_result.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/frame_resampler.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';

const folderToStep = {
  'Basico': 'basico_adelante_atras',
  'Guapeo': 'basico_guapeo',
  'Cucaracha': 'cucaracha',
  'SuzyQ': 'suzy_q',
  'RightSpotTurn': 'right_spot_turn',
  'CumbiaStep': 'cumbia_step',
  'CubanBreak': 'cuban_break',
  'GiroPuntaTalon': 'giro_punta_talon',
  'KickFlick': 'kick_flick',
};

class Label {
  const Label(this.name, this.target, this.tol, {this.weight = 1});
  final String name;
  final double target, tol, weight;
}

const lblSelf = Label('ideal', 100, 3, weight: 1);
const lblRegular = Label('regular', 75, 5, weight: 2);
const lblStudent = Label('alumno', 45, 5, weight: 3);
const lblAvril = Label('avril', 75, 8, weight: 2);
const lblStill = Label('quieto', 0, 5, weight: 2);
const lblShift = Label('desfase', 92, 6, weight: 1);
const lblSlow = Label('lento10', 85, 10, weight: 1);
const lblRandom = Label('random', 8, 8, weight: 2);

class Take {
  Take(this.key, this.frames, this.aspect);
  final String key;
  final List<List<double>> frames; // 33 x 4
  final double aspect;
  double get durationMs => frames.length * 33.0;
}

class RealCase {
  RealCase(this.step, this.take, this.label, this.user, this.ref);
  final String step;
  final Take take;
  final Label label;
  final List<List<double>> user, ref;
  String get name => take.key.split('/').last;
}

List<PoseLandmark> toLandmarks(List<double> flat) => [
      for (var i = 0; i + 3 < flat.length; i += 4)
        PoseLandmark(
            type: i ~/ 4,
            x: flat[i],
            y: flat[i + 1],
            z: flat[i + 2],
            confidence: flat[i + 3]),
    ];

/// Lo que hace la app con una captura: features por fotograma con aspecto,
/// tiempos reales, y rejilla de 33 ms de la duración de la referencia.
List<List<double>> featuresOf(Take t,
    {required int durationMs, bool mirror = false}) {
  final feats = <List<double>>[];
  final times = <int>[];
  for (var i = 0; i < t.frames.length; i++) {
    final v = FeatureExtractor.extractFeatures(toLandmarks(t.frames[i]),
        aspectRatio: t.aspect, isMirrored: mirror);
    if (v != null) {
      feats.add(v);
      times.add(i * 33);
    }
  }
  return FrameResampler.toGrid(feats, times, durationMs: durationMs);
}

Map<String, Take> loadTakes(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      e.key: Take(
        e.key,
        [
          for (final f in (e.value as Map)['frames'] as List)
            (f as List)
                .map((x) => (x as num).toDouble())
                .toList(growable: false),
        ],
        ((e.value as Map)['height'] as num? ?? 1280) /
            ((e.value as Map)['width'] as num? ?? 720),
      ),
  };
}

List<RealCase> buildCases(Map<String, Take> prof, Map<String, Take> real,
    {bool mirror = false, Set<String>? only}) {
  final cases = <RealCase>[];
  final refs = <String, List<List<double>>>{};
  for (final id in kRealStepIds) {
    if (only != null && !only.contains(id)) continue;
    final g = prof[id]!;
    final ref = featuresOf(g, durationMs: g.durationMs.round());
    refs[id] = ref;
    final dur = ref.length * 33;
    cases.add(RealCase(id, g, lblSelf, ref, ref));
    final reg = prof['${id}_regular']!;
    cases.add(RealCase(id, reg, lblRegular,
        align(featuresOf(reg, durationMs: dur), ref, id), ref));
    // Controles sintéticos: la propia referencia retrasada 330 ms y la
    // referencia un 10 % más lenta. El DTW debe absorber ambas casi del todo.
    cases.add(RealCase(id, Take('$id/desfase', const [], 1), lblShift,
        (List<List<double>>.filled(10, ref.first) + ref).sublist(0, ref.length),
        ref));
    cases.add(RealCase(id, Take('$id/lento10', const [], 1), lblSlow,
        List<List<double>>.generate(ref.length, (k) {
          final pos = k / 1.1;
          final i = pos.floor().clamp(0, ref.length - 2);
          final t = pos - i;
          return List<double>.generate(
              ref[i].length, (c) => ref[i][c] + (ref[i + 1][c] - ref[i][c]) * t);
        }),
        ref));
    // Control: quedarse quieto en la primera pose de la referencia.
    cases.add(RealCase(id, Take('$id/quieto', const [], 1), lblStill,
        List<List<double>>.filled(ref.length, ref.first), ref));
  }
  for (final e in real.entries) {
    final folder = e.key.split('/').first;
    final file = e.key.split('/').last;
    if (folder == 'randoms') {
      for (final id in refs.keys) {
        cases.add(RealCase(
            id,
            e.value,
            lblRandom,
            align(featuresOf(e.value, durationMs: refs[id]!.length * 33),
                refs[id]!, id),
            refs[id]!));
      }
      continue;
    }
    final id = folderToStep[folder];
    if (id == null || !refs.containsKey(id)) continue;
    final label = file.startsWith('Avril') ? lblAvril : lblStudent;
    cases.add(RealCase(
        id,
        e.value,
        label,
        align(
            featuresOf(e.value,
                durationMs: refs[id]!.length * 33, mirror: mirror),
            refs[id]!,
            id),
        refs[id]!));
  }
  cases.sort((a, b) {
    final s = kRealStepIds.indexOf(a.step) - kRealStepIds.indexOf(b.step);
    return s != 0 ? s : a.label.target.compareTo(b.label.target) * -1;
  });
  return cases;
}

typedef ParamsFor = DtwParams Function(String stepId);

/// --align=N: busca el desfase inicial (±N s) con el que la toma cuesta menos
/// contra la referencia y recorta/congela para dejarla en la rejilla. Sirve
/// para saber si las tomas de los alumnos arrancan a la vez que la referencia
/// (en la app el ¡YA! y la música fijan ese instante; en un video suelto no).
double alignSearchSec = 0;
final Map<String, int> chosenOffset = {};

List<List<double>> align(
    List<List<double>> user, List<List<double>> ref, String step) {
  if (alignSearchSec <= 0 || user.isEmpty) return user;
  final maxShift = (alignSearchSec * 1000 / 33).round();
  List<List<double>> shifted(int k) {
    // k > 0: la toma va adelantada (se saltan k fotogramas del principio).
    // k < 0: la toma va atrasada (se repite la primera pose k fotogramas).
    if (k >= 0) {
      final out = user.sublist(k.clamp(0, user.length - 1));
      while (out.length < ref.length) {
        out.add(out.last);
      }
      return out.sublist(0, ref.length);
    }
    final out = List<List<double>>.filled(-k, user.first) + user;
    return out.sublist(0, ref.length);
  }

  var best = user;
  var bestCost = double.infinity;
  var bestK = 0;
  for (var k = -maxShift; k <= maxShift; k += 3) {
    final u = shifted(k);
    final r = DtwComparator.compare(u, ref,
        weights: kStepWeights[step], params: DtwParams.defaults);
    if (r.relativeCost < bestCost) {
      bestCost = r.relativeCost;
      best = u;
      bestK = k;
    }
  }
  chosenOffset['$step:${user.hashCode}'] = bestK;
  return best;
}

DtwResult scoreCase(RealCase c, DtwParams p) => DtwComparator.compare(
    c.user, c.ref,
    weights: kStepWeights[c.step], params: p);

/// Nota final de un resultado ya calculado si la curva de alineación fuera
/// [p] (floor / max / power). Replica exactamente el cierre de
/// `DtwComparator.compare` (media de tramos, RNF-06) sin repetir el DTW.
int rescore(DtwResult r, DtwParams p) {
  if (r.segmentRelativeCost.isEmpty) return r.score;
  var sum = 0;
  for (var s = 0; s < 3; s++) {
    final rel = r.segmentRelativeCost[s];
    if (!rel.isFinite) continue;
    final base = DtwComparator.costToAlignScore(rel, p);
    sum += (base * r.segmentFactor[s]).round().clamp(0, 100).toInt();
  }
  final align = (sum / 3).round();
  final rhythm = (r.segmentRhythm.reduce((a, b) => a + b) / 3).round();
  return (p.alignWeight * align + p.rhythmWeight * rhythm)
      .toInt()
      .clamp(0, 100)
      .toInt();
}

double lossOfResults(List<(RealCase, DtwResult)> rs, DtwParams p) {
  var sum = 0.0, wsum = 0.0;
  for (final (c, r) in rs) {
    final err = (rescore(r, p) - c.label.target).abs() - c.label.tol;
    if (err > 0) sum += c.label.weight * err * err;
    wsum += c.label.weight;
  }
  return sum / wsum;
}

double lossOf(List<RealCase> cases, ParamsFor pf) {
  var sum = 0.0, wsum = 0.0;
  for (final c in cases) {
    final s = scoreCase(c, pf(c.step)).score;
    final err = (s - c.label.target).abs() - c.label.tol;
    if (err > 0) sum += c.label.weight * err * err;
    wsum += c.label.weight;
  }
  return sum / wsum;
}

void printTable(List<RealCase> cases, ParamsFor pf, {bool detail = false}) {
  String? lastStep;
  var inBand = 0, total = 0;
  final perLabel = <String, List<double>>{};
  final perLabelRel = <String, List<double>>{};
  final perLabelAli = <String, List<double>>{};
  final perLabelRit = <String, List<double>>{};
  for (final c in cases) {
    if (c.step != lastStep) {
      stdout.writeln('\n${c.step}  ${pf(c.step)}');
      stdout.writeln(
          '  ${'toma'.padRight(46)} ${'etq'.padRight(8)} obj   nota  ali  rit   rel  cov  mir  dev  seg');
      lastStep = c.step;
    }
    final r = scoreCase(c, pf(c.step));
    final ok = (r.score - c.label.target).abs() <= c.label.tol;
    if (ok) inBand++;
    total++;
    perLabel.putIfAbsent(c.label.name, () => []).add(r.score.toDouble());
    perLabelRel.putIfAbsent(c.label.name, () => []).add(r.relativeCost);
    perLabelAli.putIfAbsent(c.label.name, () => []).add(r.alignmentScore.toDouble());
    perLabelRit.putIfAbsent(c.label.name, () => []).add(r.rhythmScore.toDouble());
    final extra = detail
        ? '  peor ${DtwResult.componentNames[r.worstComponentIndex]}'
            '  ali/seg ${r.segmentAlignment} rit/seg ${r.segmentRhythm}'
        : '';
    stdout.writeln('  ${c.name.padRight(46)} ${c.label.name.padRight(8)} '
        '${c.label.target.round().toString().padLeft(3)}  '
        '${r.score.toString().padLeft(4)}${ok ? ' ' : '!'} '
        '${r.alignmentScore.toString().padLeft(3)}  '
        '${r.rhythmScore.toString().padLeft(3)}  '
        '${r.relativeCost.toStringAsFixed(2)} ${r.coverage.toStringAsFixed(2)} '
        '${r.mirrorFactor.toStringAsFixed(2)} ${r.pathDeviation.toStringAsFixed(3)} ${r.segmentScore}$extra');
  }
  stdout.writeln(
      '\nen banda $inBand/$total   loss ${lossOf(cases, pf).toStringAsFixed(1)}');
  for (final e in perLabel.entries) {
    final xs = e.value..sort();
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    final rel = perLabelRel[e.key]!..sort();
    stdout.writeln('  ${e.key.padRight(8)} n=${xs.length.toString().padLeft(2)}  '
        'media ${mean.toStringAsFixed(1).padLeft(5)}  '
        'min ${xs.first.round().toString().padLeft(3)}  max ${xs.last.round().toString().padLeft(3)}'
        '   ali ${avg(perLabelAli[e.key]!).toStringAsFixed(0).padLeft(3)}'
        '  rit ${avg(perLabelRit[e.key]!).toStringAsFixed(0).padLeft(3)}'
        '   rel media ${avg(rel).toStringAsFixed(2)} [${rel.first.toStringAsFixed(2)}-${rel.last.toStringAsFixed(2)}]');
  }
}

/// --fit: por paso, floor y max que minimizan la pérdida de SUS tomas. El DTW
/// se corre una vez por toma con los parámetros globales; la curva se
/// re-mapea con [rescore], así que la rejilla puede ser fina.
/// Límites del ajuste por paso: el suelo nunca por encima de [kFloorMax]
/// (0.9 es el coste de la toma regular de la profesora: por debajo tiene que
/// haber curva, no meseta) y un tramo mínimo [kMinSpan] entre suelo y techo
/// para que la nota no sea un acantilado.
const double kFloorMax = 0.7;
const double kMinSpan = 0.4;

Map<String, DtwParams> fitPerStep(List<RealCase> cases, DtwParams global,
    {double step = 0.02, Map<RealCase, DtwResult>? cache}) {
  final fitted = <String, DtwParams>{};
  for (final id in kRealStepIds) {
    final mine = [
      for (final c in cases)
        if (c.step == id) (c, cache?[c] ?? scoreCase(c, global)),
    ];
    if (mine.isEmpty) continue;
    DtwParams? best;
    var bestLoss = double.infinity;
    for (var floor = 0.05; floor <= kFloorMax + 1e-4; floor += step) {
      for (var max = floor + kMinSpan; max <= 2.2001; max += step) {
        final p = global.copyWith(alignNoiseFloor: floor, alignMax: max);
        final l = lossOfResults(mine, p);
        if (l < bestLoss - 1e-9) {
          bestLoss = l;
          best = p;
        }
      }
    }
    fitted[id] = best!;
  }
  return fitted;
}

/// --fitglobal: UNA sola curva (floor, max) para los nueve pasos. El coste
/// relativo ya está en una escala común, así que una curva global es más
/// defendible que nueve ajustadas a 3-4 tomas cada una.
void fitGlobal(List<RealCase> cases, DtwParams global) {
  final rs = [for (final c in cases) (c, scoreCase(c, global))];
  DtwParams? best;
  var bestLoss = double.infinity;
  for (var floor = 0.05; floor <= 1.2001; floor += 0.01) {
    for (var max = floor + 0.2; max <= 2.5001; max += 0.01) {
      final p = global.copyWith(alignNoiseFloor: floor, alignMax: max);
      final l = lossOfResults(rs, p);
      if (l < bestLoss - 1e-9) {
        bestLoss = l;
        best = p;
      }
    }
  }
  final b = best!;
  printTable(cases, (_) => b);
  stdout.writeln('// global: floor ${b.alignNoiseFloor.toStringAsFixed(2)} '
      'max ${b.alignMax.toStringAsFixed(2)}  loss ${bestLoss.toStringAsFixed(1)}');
}

void fit(List<RealCase> cases, DtwParams global) {
  final fitted = fitPerStep(cases, global);
  printTable(cases, (id) => fitted[id] ?? global);
  stdout.writeln('\n// step_params.dart');
  for (final e in fitted.entries) {
    stdout.writeln(
        "  '${e.key}': (floor: ${e.value.alignNoiseFloor.toStringAsFixed(3)}, "
        "max: ${e.value.alignMax.toStringAsFixed(3)}),");
  }
}

/// --sweep: barrido por coordenadas de los parámetros globales, ajustando
/// floor/max por paso en cada candidato (lo que de verdad irá a producción).
void sweep(List<RealCase> cases, DtwParams start) {
  double evalGlobal(DtwParams g) {
    final cache = {for (final c in cases) c: scoreCase(c, g)};
    final fitted = fitPerStep(cases, g, step: 0.04, cache: cache);
    var sum = 0.0, wsum = 0.0;
    for (final c in cases) {
      final p = fitted[c.step] ?? g;
      final err = (rescore(cache[c]!, p) - c.label.target).abs() - c.label.tol;
      if (err > 0) sum += c.label.weight * err * err;
      wsum += c.label.weight;
    }
    return sum / wsum;
  }

  var best = start;
  var bestLoss = evalGlobal(best);
  stdout.writeln('inicio loss ${bestLoss.toStringAsFixed(1)}');
  final axes = <String, List<DtwParams Function(DtwParams)>>{
    'pow': [
      for (final v in [0.6, 0.8, 1.0, 1.25, 1.5, 2.0])
        (p) => p.copyWith(alignCurvePower: v)
    ],
    'clip': [
      for (final v in [1.0, 1.5, 2.0, 3.0, 4.0])
        (p) => p.copyWith(featureClip: v)
    ],
    'off': [
      for (final v in [0.0, 0.05, 0.1, 0.25, 0.5])
        (p) => p.copyWith(offsetWeight: v)
    ],
    'band': [
      for (final v in [0.08, 0.12, 0.16, 0.2, 0.25])
        (p) => p.copyWith(bandRatio: v)
    ],
    'covZ': [
      for (final v in [0.05, 0.15, 0.25, 0.35])
        (p) => p.copyWith(coverageZeroRatio: v)
    ],
    'covF': [
      for (final v in [0.35, 0.45, 0.55, 0.65, 0.8])
        (p) => p.copyWith(coverageFullRatio: v)
    ],
    'covMin': [
      for (final v in [0.0, 0.2, 0.4]) (p) => p.copyWith(coverageMinFactor: v)
    ],
    'rhyZ': [
      for (final v in [-0.2, 0.0, 0.1, 0.2, 0.3])
        (p) => p.copyWith(rhythmCorrZero: v)
    ],
    'rhyF': [
      for (final v in [0.3, 0.4, 0.5, 0.6, 0.7, 0.8])
        (p) => p.copyWith(rhythmCorrFull: v)
    ],
    'lag': [for (final v in [2, 4, 8, 12]) (p) => p.copyWith(rhythmMaxLag: v)],
    'rhyW': [
      for (final v in [30, 45, 60, 90]) (p) => p.copyWith(rhythmWindow: v)
    ],
    'rhyS': [for (final v in [3, 5, 9]) (p) => p.copyWith(rhythmSmooth: v)],
    'k': [for (final v in [2.0, 4.0, 8.0, 16.0]) (p) => p.copyWith(snrK: v)],
    'ampN': [
      for (final v in [1.0, 2.0, 3.0, 5.0])
        (p) => p.copyWith(amplitudeNoiseMul: v)
    ],
    'smooth': [
      for (final v in [3, 5, 7, 9, 11]) (p) => p.copyWith(smoothWindow: v)
    ],
    'uamp': [
      for (final v in [true, false])
        (p) => p.copyWith(userAmplitudeNormalize: v)
    ],
  };
  for (var round = 0; round < 3; round++) {
    var improved = false;
    for (final e in axes.entries) {
      for (final f in e.value) {
        final cand = f(best);
        final l = evalGlobal(cand);
        if (l < bestLoss - 1e-6) {
          bestLoss = l;
          best = cand;
          improved = true;
          stdout.writeln(
              '  ${e.key.padRight(6)} -> loss ${l.toStringAsFixed(1)}  $best');
        }
      }
    }
    if (!improved) break;
  }
  stdout.writeln('\nmejor global: $best');
  fit(cases, best);
}

/// --features: de qué features sale el error de cada toma (componentErrors,
/// error absoluto ponderado medio a lo largo del camino DTW) y cuánto se mueve
/// el usuario frente al modelo en cada una (desviación típica usuario/modelo).
void printFeatures(List<RealCase> cases, ParamsFor pf) {
  double stdOf(List<List<double>> f, int c) {
    var m = 0.0;
    for (final x in f) {
      m += x[c];
    }
    m /= f.length;
    var v = 0.0;
    for (final x in f) {
      v += (x[c] - m) * (x[c] - m);
    }
    return (v / f.length).sqrt();
  }

  for (final c in cases) {
    if (c.label == lblSelf || c.label == lblStill || c.label == lblShift || c.label == lblSlow) continue;
    final r = scoreCase(c, pf(c.step));
    final w = kStepWeights[c.step]!;
    stdout.writeln('\n${c.step} / ${c.name} [${c.label.name}] nota ${r.score} '
        'ali ${r.alignmentScore} rit ${r.rhythmScore} rel ${r.relativeCost.toStringAsFixed(2)}');
    final idx = List<int>.generate(r.componentErrors.length, (i) => i)
      ..sort((a, b) => r.componentErrors[b].compareTo(r.componentErrors[a]));
    final total = r.componentErrors.reduce((a, b) => a + b);
    for (final i in idx.take(8)) {
      final su = stdOf(c.user, i), sr = stdOf(c.ref, i);
      stdout.writeln('   ${i.toString().padLeft(2)} ${DtwResult.componentNames[i].padRight(40)} '
          'w ${w[i].toStringAsFixed(2)}  err ${(100 * r.componentErrors[i] / total).toStringAsFixed(0).padLeft(3)}%'
          '  amp usr/ref ${(su / (sr + 1e-9)).toStringAsFixed(2)}');
    }
  }
}

extension on double {
  double sqrt() => this <= 0 ? 0 : math.sqrt(this);
}

void main(List<String> args) {
  final prof = loadTakes('tool/landmarks.json');
  final real = loadTakes('tool/landmarks_revisados.json');
  final alignArg = args.where((a) => a.startsWith('--align=')).toList();
  if (alignArg.isNotEmpty) {
    alignSearchSec = double.parse(alignArg.first.substring(8));
  }
  final stepArg = args.where((a) => a.startsWith('--step=')).toList();
  final only = stepArg.isEmpty ? null : {stepArg.first.substring(7)};
  final cases =
      buildCases(prof, real, mirror: args.contains('--mirror'), only: only);
  double? num(String flag) {
    final a = args.where((e) => e.startsWith('--$flag=')).toList();
    return a.isEmpty ? null : double.parse(a.first.split('=')[1]);
  }

  int? inum(String flag) => num(flag)?.round();
  DtwParams override(DtwParams p) => p.copyWith(
        alignNoiseFloor: num('nf'),
        alignMax: num('max'),
        alignCurvePower: num('pow'),
        featureClip: num('clip'),
        offsetWeight: num('off'),
        bandRatio: num('band'),
        coverageZeroRatio: num('covZ'),
        coverageFullRatio: num('covF'),
        coverageMinFactor: num('covMin'),
        rhythmCorrZero: num('rhyZ'),
        rhythmCorrFull: num('rhyF'),
        rhythmMaxLag: inum('lag'),
        rhythmWindow: inum('rhyW'),
        snrK: num('k'),
        amplitudeNoiseMul: num('ampN'),
        smoothWindow: inum('smooth'),
        amplitudeNormalize: args.contains('--noamp') ? false : null,
        userAmplitudeNormalize: args.contains('--uamp') ? true : null,
        centerFeatures: args.contains('--nocenter') ? false : null,
      );
  final base = override(DtwParams.defaults);
  stdout.writeln('casos: ${cases.length}');
  if (args.contains('--features')) {
    return printFeatures(cases, args.contains('--global') ? (_) => base : (id) => override(paramsFor(id)));
  }
  if (args.contains('--fitglobal')) return fitGlobal(cases, base);
  if (args.contains('--fit')) return fit(cases, base);
  if (args.contains('--sweep')) return sweep(cases, base);
  final global = args.contains('--global');
  printTable(cases, global ? (_) => base : (id) => override(paramsFor(id)),
      detail: args.contains('--detail'));
}
