/// Banco con TOMAS REALES ETIQUETADAS (implementar_pasos.txt §7-sexies).
///
/// `bench.dart` fabricaba al alumno a partir de la propia profesora. Este banco
/// usa grabaciones de alumnos reales (BailonGObailes/BailesREVISADOS, extraídas
/// con `tool/extract_revisados.py`) con la nota que les dio la revisión humana.
///
/// Las notas por toma viven en `tool/labels.json` (lo genera y documenta
/// `tool/build_labels.py`, y se puede editar a mano). Cubren de 2/10 a 8/10,
/// así que desde la segunda vuelta (2026-10-05) la escala tiene puntos de
/// anclaje en todo el rango y no solo abajo. Una toma con `score: null` se
/// evalúa y se imprime pero NO cuenta en la pérdida.
///
/// Lo que sigue en código, por ser estructural y no juicio humano:
///   ideal vs sí misma ... 100   control de consistencia del motor
///   toma regular ........  75   la "imperfecta" de la profesora (7-8/10)
///   quieto ..............   0   no moverse
///   desfase .............  92   la referencia retrasada 330 ms
///   lento10 .............  85   la referencia un 10 % más lenta
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
  const Label(this.name, this.target, this.tol,
      {this.weight = 1, this.scored = true, this.direct = false});
  final String name;

  /// Nota humana (0-100) y margen sin castigo. Con [scored] en falso la toma
  /// se evalúa y se imprime, pero no entra en la pérdida: no hay etiqueta.
  final double target, tol, weight;
  final bool scored;

  /// La nota viene del revisor para ESA toma, no de una banda supuesta. Es el
  /// único subconjunto con el que tiene sentido medir si el motor ordena como
  /// una persona.
  final bool direct;
}

const lblSelf = Label('ideal', 100, 3, weight: 1);
// Peso alto a propósito: es la ÚNICA toma del corpus que la propia experta
// calificó, y marca dónde está el 75 %. Con peso 2 el ajuste la sacrificaba
// para perseguir notas de alumno que quedaban fuera de alcance de todos
// modos, y acabó dándole 90 a la ejecución que la experta puntuó 7-8.
const lblRegular = Label('regular', 75, 5, weight: 6);
/// Las nueve tomas de `bailes10profacalibracion`. La experta las dio por
/// perfectas, así que marcan dónde empieza el sobresaliente. Objetivo 95 y no
/// 100 porque son una ejecución DISTINTA de la referencia: pedir el 100 sería
/// pedirle al motor que ignore toda diferencia entre dos pasadas del mismo
/// paso, que es justo lo que separa un 10 de un 7.
/// Peso de las tomas de 10 en la pérdida (--peso10=N). 8 medido: con 4 el
/// ajuste las deja en 84.7 de media y con 14 solo sube a 85.9, así que 8 es
/// donde deja de pagar; los bailes ajenos no se mueven (17.9 de media).
double kPeso10 = 8;
const lblStill = Label('quieto', 0, 5, weight: 2);
const lblShift = Label('desfase', 92, 6, weight: 1);
const lblSlow = Label('lento10', 85, 10, weight: 1);

/// Control del extremo ALTO de la escala: la propia referencia tal como
/// saldría de una captura real, con el temblor del detector, una complexión
/// algo distinta y un pequeño retraso de reacción. Equivale a la profesora
/// repitiendo su propio paso delante del teléfono.
///
/// Hace falta porque el resto del corpus no dice dónde empieza el sobresaliente:
/// la referencia contra sí misma da 100 con cualquier umbral, por lo que no
/// aporta información al ajuste, y la mejor ejecución humana disponible está
/// calificada con 8 sobre 10. Sin este control, el ajuste no tiene motivo
/// para dejar alcanzable el 90 % y la escala se cierra por arriba.
const lblGreat = Label('excelente', 95, 5, weight: 3);

bool kHighPriority = false;

/// Notas de `tool/labels.json`, por clave "<Carpeta>/<archivo sin extensión>".
Map<String, Label> loadLabels(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final out = <String, Label>{};
  for (final e in raw.entries) {
    final v = e.value as Map<String, dynamic>;
    final score = (v['score'] as num?)?.toDouble();
    final folder = e.key.split('/').first;
    final file = e.key.split('/').last.toLowerCase();
    // El nombre del grupo solo sirve para agregar en la tabla resumen.
    final who = folder == 'randoms'
        ? 'ajeno'
        : file.startsWith('profa')
            ? 'profa10'
            : file.startsWith('abdiel') || file.startsWith('adbiel')
                ? 'abdiel'
                : file.startsWith('avril')
                    ? 'avril'
                    : file.startsWith('gabo')
                        ? 'gabo'
                        : file.startsWith('primo')
                            ? 'primo'
                            : file.startsWith('toto')
                                ? 'toto'
                                : 'otro';
    out[e.key] = Label(
      who,
      score ?? 0,
      (v['tol'] as num?)?.toDouble() ?? 7,
      // --priorizaalto: el ajuste atiende antes a las tomas bien calificadas
      // que a las flojas. Es una decisión de producto, no una medición: vale
      // más no castigar a quien baila bien que clavar la nota de quien baila
      // mal, porque el alumno abandona por lo primero.
      weight: score == null
          ? 0
          // La tanda de 10 de la profesora es el ancla del extremo alto: pesa
          // como la toma imperfecta que calificó ella misma, no como una toma
          // de alumno. Medido: con peso 4 el ajuste las deja 1 punto por
          // debajo y con 14 solo medio punto por encima.
          : who == 'profa10'
              ? kPeso10
              : (kHighPriority && score >= 70)
                  ? 6
                  : 2,
      scored: score != null,
      direct: (v['src'] as String? ?? '').contains('revisor'),
    );
  }
  return out;
}

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
    Map<String, Label> labels,
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
    // Control del extremo alto: dos variantes de la referencia con ruido de
    // captura y amplitud algo distinta (ver [lblGreat]).
    for (final v in const [(0.92, 11), (1.08, 12)]) {
      cases.add(RealCase(
          id,
          Take('$id/excelente', const [], g.aspect),
          lblGreat,
          featuresOf(
              Take('$id/excelente', liveLike(g.frames, v.$1, v.$2), g.aspect),
              durationMs: dur),
          ref));
    }
    // Control: quedarse quieto en la primera pose de la referencia.
    cases.add(RealCase(id, Take('$id/quieto', const [], 1), lblStill,
        List<List<double>>.filled(ref.length, ref.first), ref));
  }
  for (final e in real.entries) {
    final folder = e.key.split('/').first;
    if (folder == 'randoms') {
      for (final id in refs.keys) {
        cases.add(RealCase(
            id,
            e.value,
            labels[e.key]!,
            align(featuresOf(e.value, durationMs: refs[id]!.length * 33),
                refs[id]!, id),
            refs[id]!));
      }
      continue;
    }
    final id = folderToStep[folder];
    if (id == null || !refs.containsKey(id)) continue;
    final label = labels[e.key];
    if (label == null) {
      stderr.writeln('!! sin etiqueta en labels.json: ${e.key} '
          '(corre: python tool/build_labels.py)');
      continue;
    }
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

/// Devuelve los landmarks de [frames] como los entregaría una captura real de
/// la misma ejecución: amplitud del movimiento escalada por [amp] respecto a
/// la postura media, temblor correlacionado del detector y un retraso de
/// reacción de cinco fotogramas. El escalado se hace respecto a la postura
/// media y no al centro de la cadera, para cambiar cuánto se mueve el cuerpo y
/// no su tamaño.
List<List<double>> liveLike(List<List<double>> frames, double amp, int seed) {
  const n = 33;
  const sigmaJoint = 0.0025, sigmaFoot = 0.005;
  const lag = 5;
  final rng = math.Random(seed);
  double gauss() {
    final u1 = rng.nextDouble().clamp(1e-12, 1.0);
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rng.nextDouble());
  }

  // Postura media de cada landmark respecto al centro de la cadera.
  final mean = List<double>.filled(n * 2, 0);
  for (final f in frames) {
    final hx = (f[23 * 4] + f[24 * 4]) / 2;
    final hy = (f[23 * 4 + 1] + f[24 * 4 + 1]) / 2;
    for (var i = 0; i < n; i++) {
      mean[i * 2] += f[i * 4] - hx;
      mean[i * 2 + 1] += f[i * 4 + 1] - hy;
    }
  }
  for (var k = 0; k < mean.length; k++) {
    mean[k] /= math.max(frames.length, 1);
  }

  final nx = List<double>.filled(n, 0), ny = List<double>.filled(n, 0);
  return List<List<double>>.generate(frames.length, (t) {
    final src = frames[math.max(0, t - lag)];
    final out = List<double>.from(src);
    final hx = (src[23 * 4] + src[24 * 4]) / 2;
    final hy = (src[23 * 4 + 1] + src[24 * 4 + 1]) / 2;
    for (var i = 0; i < n; i++) {
      final sigma = i >= 27 ? sigmaFoot : sigmaJoint;
      nx[i] = 0.6 * nx[i] + 0.8 * sigma * gauss();
      ny[i] = 0.6 * ny[i] + 0.8 * sigma * gauss();
      final mx = mean[i * 2], my = mean[i * 2 + 1];
      out[i * 4] = hx + mx + (src[i * 4] - hx - mx) * amp + nx[i];
      out[i * 4 + 1] = hy + my + (src[i * 4 + 1] - hy - my) * amp + ny[i];
    }
    return out;
  });
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

/// Multiplicador por GRUPO de características, común a los nueve pasos. Se
/// aplica encima de `kStepWeights`, así que la jerarquía razonada por paso se
/// conserva y lo que se ajusta es cuánto vale cada parte del cuerpo en
/// conjunto. `--wsweep` lo busca contra el corpus etiquetado.
const featureGroups = kFeatureGroups;
Map<String, double> groupMul = Map<String, double>.from(kGroupScale);

List<double> weightsFor(String step) {
  final base = kStepWeights[step]!;
  final out = List<double>.from(base);
  for (final e in featureGroups.entries) {
    final m = groupMul[e.key] ?? 1.0;
    for (final i in e.value) {
      out[i] = base[i] * m;
    }
  }
  return out;
}

DtwResult scoreCase(RealCase c, DtwParams p) => DtwComparator.compare(
    c.user, c.ref,
    weights: weightsFor(c.step), params: p);

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
    if (!c.label.scored) continue;
    final err = (rescore(r, p) - c.label.target).abs() - c.label.tol;
    if (err > 0) sum += c.label.weight * err * err;
    wsum += c.label.weight;
  }
  return sum / wsum;
}

double lossOf(List<RealCase> cases, ParamsFor pf) {
  var sum = 0.0, wsum = 0.0;
  for (final c in cases) {
    if (!c.label.scored) continue;
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
  final humano = <double>[], motor = <double>[];
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
    final ok = c.label.scored && (r.score - c.label.target).abs() <= c.label.tol;
    if (c.label.scored) {
      if (ok) inBand++;
      total++;
      humano.add(c.label.target);
      motor.add(r.score.toDouble());
    }
    perLabel.putIfAbsent(c.label.name, () => []).add(r.score.toDouble());
    perLabelRel.putIfAbsent(c.label.name, () => []).add(r.relativeCost);
    perLabelAli.putIfAbsent(c.label.name, () => []).add(r.alignmentScore.toDouble());
    perLabelRit.putIfAbsent(c.label.name, () => []).add(r.rhythmScore.toDouble());
    final extra = detail
        ? '  peor ${DtwResult.componentNames[r.worstComponentIndex]}'
            '  ali/seg ${r.segmentAlignment} rit/seg ${r.segmentRhythm}'
        : '';
    stdout.writeln('  ${c.name.padRight(46)} ${c.label.name.padRight(8)} '
        '${c.label.scored ? c.label.target.round().toString().padLeft(3) : '  -'}  '
        '${r.score.toString().padLeft(4)}${ok ? ' ' : '!'} '
        '${r.alignmentScore.toString().padLeft(3)}  '
        '${r.rhythmScore.toString().padLeft(3)}  '
        '${r.relativeCost.toStringAsFixed(2)} ${r.coverage.toStringAsFixed(2)} '
        '${r.mirrorFactor.toStringAsFixed(2)} ${r.pathDeviation.toStringAsFixed(3)} ${r.segmentScore}$extra');
  }
  stdout.writeln('\nen banda $inBand/$total   '
      'loss ${lossOf(cases, pf).toStringAsFixed(1)}   '
      'r ${_pearson(motor, humano).toStringAsFixed(2)}   '
      'rho ${_spearman(motor, humano).toStringAsFixed(2)}   '
      'error medio ${_mae(motor, humano).toStringAsFixed(1)}');
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

/// --wsweep: busca el multiplicador de cada grupo de características que
/// mejor reproduce el juicio humano. En cada candidato se reajustan los dos
/// umbrales de cada paso, que es lo que de verdad iría a producción.
void weightSweep(List<RealCase> cases, DtwParams base) {
  double evalMul() {
    final cache = {for (final c in cases) c: scoreCase(c, base)};
    final fitted = fitPerStep(cases, base, step: 0.04, cache: cache);
    var sum = 0.0, wsum = 0.0;
    for (final c in cases) {
      if (!c.label.scored) continue;
      final p = fitted[c.step] ?? base;
      final err = (rescore(cache[c]!, p) - c.label.target).abs() - c.label.tol;
      if (err > 0) sum += c.label.weight * err * err;
      wsum += c.label.weight;
    }
    return sum / wsum;
  }

  final best = Map<String, double>.from(groupMul);
  var bestLoss = evalMul();
  stdout.writeln('inicio loss ${bestLoss.toStringAsFixed(1)}');
  const vals = [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 4.0];
  for (var round = 0; round < 3; round++) {
    var improved = false;
    for (final g in featureGroups.keys) {
      final keep = best[g]!;
      var bestV = keep;
      for (final v in vals) {
        groupMul = Map<String, double>.from(best)..[g] = v;
        final l = evalMul();
        if (l < bestLoss - 1e-6) {
          bestLoss = l;
          bestV = v;
          improved = true;
        }
      }
      best[g] = bestV;
      groupMul = Map<String, double>.from(best);
      if (bestV != keep) {
        stdout.writeln('  ${g.padRight(10)} x$bestV -> loss '
            '${bestLoss.toStringAsFixed(1)}');
      }
    }
    if (!improved) break;
  }
  groupMul = best;
  stdout.writeln('\n// multiplicador por grupo');
  for (final e in best.entries) {
    stdout.writeln('  ${e.key}: ${e.value},');
  }
  printSep(cases, (_) => base, 'con esos pesos');
  fit(cases, base);
}

/// --perfeature: poder discriminante de CADA característica por separado.
/// Para cada una se evalúa el corpus con esa sola característica activa y se
/// compara el costo medio de lo que el revisor puntuó alto contra lo que
/// puntuó bajo. Positivo = esa característica ordena como la persona.
void printPerFeature(List<RealCase> cases, DtwParams base) {
  stdout.writeln('  #  característica                              '
      'alto   bajo    separación');
  final rank = <(double, String)>[];
  for (var c = 0; c < FeatureExtractor.featureCount; c++) {
    final w = List<double>.filled(FeatureExtractor.featureCount, 0)..[c] = 1;
    final alto = <double>[], bajo = <double>[];
    for (final cs in cases) {
      if (!cs.label.direct) continue;
      final r = DtwComparator.compare(cs.user, cs.ref, weights: w, params: base);
      if (!r.relativeCost.isFinite) continue;
      (cs.label.target >= 60 ? alto : cs.label.target <= 30 ? bajo : <double>[])
          .add(r.relativeCost);
    }
    if (alto.isEmpty || bajo.isEmpty) continue;
    double m(List<double> x) => x.reduce((a, b) => a + b) / x.length;
    final d = m(bajo) - m(alto);
    final line = '${c.toString().padLeft(3)}  '
        '${DtwResult.componentNames[c].padRight(42)}'
        '${m(alto).toStringAsFixed(2).padLeft(5)}  '
        '${m(bajo).toStringAsFixed(2).padLeft(5)}   '
        '${d >= 0 ? '+' : ''}${d.toStringAsFixed(3)}';
    rank.add((d, line));
  }
  rank.sort((a, b) => b.$1.compareTo(a.$1));
  for (final r in rank) {
    stdout.writeln(r.$2);
  }
}

/// --sep: ¿separa el motor lo que el revisor puntuó alto de lo que puntuó
/// bajo? Solo cuenta las tomas con nota directa del revisor. Si el costo
/// medio del grupo alto no queda claramente por debajo del grupo bajo, ningún
/// ajuste de la curva puede ordenarlos: el problema es la representación.
void printSep(List<RealCase> cases, ParamsFor pf, String tag) {
  final alto = <double>[], bajo = <double>[];
  final altoN = <double>[], bajoN = <double>[];
  for (final c in cases) {
    if (!c.label.direct) continue;
    final r = scoreCase(c, pf(c.step));
    if (c.label.target >= 60) {
      alto.add(r.relativeCost);
      altoN.add(r.score.toDouble());
    } else if (c.label.target <= 30) {
      bajo.add(r.relativeCost);
      bajoN.add(r.score.toDouble());
    }
  }
  double m(List<double> x) => x.reduce((a, b) => a + b) / x.length;
  final d = m(bajo) - m(alto); // positivo = el motor acierta el orden
  stdout.writeln('${tag.padRight(34)} '
      'alto n=${alto.length} coste ${m(alto).toStringAsFixed(3)} nota ${m(altoN).toStringAsFixed(0)}  |  '
      'bajo n=${bajo.length} coste ${m(bajo).toStringAsFixed(3)} nota ${m(bajoN).toStringAsFixed(0)}  |  '
      'separación ${d >= 0 ? '+' : ''}${d.toStringAsFixed(3)}');
}

/// --csv: una línea por toma, para analizar fuera (acuerdo por bailarín, por
/// paso, sesgos...). Las tomas sin etiqueta salen con humano vacío.
void printCsv(List<RealCase> cases, ParamsFor pf) {
  stdout.writeln('paso,grupo,toma,humano,nota,ali,rit,rel,cov,mir');
  for (final c in cases) {
    final r = scoreCase(c, pf(c.step));
    final h = c.label.scored ? c.label.target.round().toString() : '';
    stdout.writeln('${c.step},${c.label.name},"${c.name}",$h,${r.score},'
        '${r.alignmentScore},${r.rhythmScore},'
        '${r.relativeCost.toStringAsFixed(4)},'
        '${r.coverage.toStringAsFixed(4)},'
        '${r.mirrorFactor.toStringAsFixed(4)}');
  }
}

/// Acuerdo con el juicio humano sobre las tomas etiquetadas. `r` mide si la
/// nota del motor sigue a la del revisor; `rho` (Spearman) si al menos las
/// ORDENA igual, que es lo que de verdad le importa al alumno.
double _pearson(List<double> a, List<double> b) {
  if (a.length < 2) return 0;
  final ma = a.reduce((x, y) => x + y) / a.length;
  final mb = b.reduce((x, y) => x + y) / b.length;
  var sab = 0.0, saa = 0.0, sbb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final da = a[i] - ma, db = b[i] - mb;
    sab += da * db;
    saa += da * da;
    sbb += db * db;
  }
  if (saa <= 1e-12 || sbb <= 1e-12) return 0;
  return sab / math.sqrt(saa * sbb);
}

List<double> _ranks(List<double> x) {
  final idx = List<int>.generate(x.length, (i) => i)
    ..sort((i, j) => x[i].compareTo(x[j]));
  final out = List<double>.filled(x.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && x[idx[j + 1]] == x[idx[i]]) {
      j++;
    }
    final r = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      out[idx[k]] = r;
    }
    i = j + 1;
  }
  return out;
}

double _spearman(List<double> a, List<double> b) =>
    a.length < 2 ? 0 : _pearson(_ranks(a), _ranks(b));

double _mae(List<double> a, List<double> b) {
  if (a.isEmpty) return 0;
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s / a.length;
}

/// --fit: por paso, floor y max que minimizan la pérdida de SUS tomas. El DTW
/// se corre una vez por toma con los parámetros globales; la curva se
/// re-mapea con [rescore], así que la rejilla puede ser fina.
/// Límites del ajuste por paso: el suelo nunca por encima de [kFloorMax] y un
/// tramo mínimo [kMinSpan] entre suelo y techo, para que la nota no sea un
/// acantilado. El suelo se amplió a 1.0 cuando entró el control [lblGreat]:
/// una captura real de la propia referencia ya cuesta del orden de la mitad de
/// lo que cuesta quedarse quieto, así que con el tope anterior de 0.7 el
/// sobresaliente quedaba fuera de alcance por construcción.
const double kFloorMax = 1.0;
// Recorrido mínimo entre el 100 y el 0 de la curva. Subido de 0.4 a 0.8 el
// 2026-10-21: con 0.54 el Right Spot Turn se volvió un acantilado y un
// intento decente marcaba 13 o 0 de alineación en el teléfono.
const double kMinSpan = 0.8;

/// El umbral de "ejecución perfecta" de un paso no puede superar esta
/// fracción de lo que cuesta su toma imperfecta. Sin la restricción, el
/// ajuste subía el umbral del Right Spot Turn a 0.89 persiguiendo las tomas
/// de alumno, que están en 1.19-1.48 y quedaban fuera de alcance de todos
/// modos; lo único que conseguía era regalarle el 94 de alineación a la
/// ejecución que la experta puntuó 7-8, que acabó con un 90. Bajarlo no
/// cuesta nada en el extremo alto: el control de captura real de la
/// referencia cuesta 0.29 y sigue en 100.
const double kFloorVsRegular = 0.95;

Map<String, DtwParams> fitPerStep(List<RealCase> cases, DtwParams global,
    {double step = 0.02, Map<RealCase, DtwResult>? cache}) {
  final fitted = <String, DtwParams>{};
  for (final id in kRealStepIds) {
    final mine = [
      for (final c in cases)
        if (c.step == id) (c, cache?[c] ?? scoreCase(c, global)),
    ];
    if (mine.isEmpty) continue;
    // Tope derivado del dato: ver [kFloorVsRegular].
    var floorCap = kFloorMax;
    for (final (c, r) in mine) {
      if (c.label == lblRegular && r.relativeCost.isFinite) {
        floorCap = math.min(floorCap, r.relativeCost * kFloorVsRegular);
      }
    }
    DtwParams? best;
    var bestLoss = double.infinity;
    for (var floor = 0.05; floor <= floorCap + 1e-4; floor += step) {
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
    if (c.label == lblSelf ||
        c.label == lblGreat ||
        c.label == lblStill ||
        c.label == lblShift ||
        c.label == lblSlow) {
      continue;
    }
    final r = scoreCase(c, pf(c.step));
    final w = weightsFor(c.step);
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
  kHighPriority = args.contains('--priorizaalto');
  final peso = args.where((a) => a.startsWith('--peso10=')).toList();
  if (peso.isNotEmpty) kPeso10 = double.parse(peso.first.substring(9));
  final labels = loadLabels('tool/labels.json');
  final cases = buildCases(prof, real, labels,
      mirror: args.contains('--mirror'), only: only);
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
        userAmplitudeNormalize: args.contains('--nouamp') ? false : null,
        centerFeatures: args.contains('--nocenter') ? false : null,
        // --ritglobal: el ritmo global deja de ser la media de los tres
        // tramos y pasa a ser la correlación ponderada de toda la toma. La
        // media castiga con 33 puntos un solo tramo malo, que es justo lo que
        // le pasa a una toma que termina tarde.
        globalFromSegments: args.contains('--ritglobal') ? false : null,
      );
  final base = override(DtwParams.defaults);
  stdout.writeln('casos: ${cases.length}');
  if (args.contains('--wsweep')) {
    return weightSweep(cases, base);
  }
  if (args.contains('--perfeature')) {
    return printPerFeature(cases, base);
  }
  if (args.contains('--sep')) {
    return printSep(cases, (_) => base, args.join(' ').replaceAll('--sep', '').trim());
  }
  if (args.contains('--csv')) {
    return printCsv(cases,
        args.contains('--global') ? (_) => base : (id) => override(paramsFor(id)));
  }
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
