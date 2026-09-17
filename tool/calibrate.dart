/// Banco de calibración en PC (implementar_pasos.txt §7).
///
/// HISTÓRICO (§7-ter). Sustituido por `tool/bench.dart` (§7-quater): este
/// banco solo mide ideal-vs-ideal y regular-vs-ideal, y su `--fit` genera los
/// parámetros del motor anterior. No pegar su salida en step_params.dart.
///
/// Corre el motor REAL de producción (`FeatureExtractor` + `DtwComparator`,
/// importados de lib/) sobre los landmarks que `tool/extract_landmarks.py`
/// volcó a JSON. No reimplementa nada: lo que se mide aquí es exactamente lo
/// que hará la app.
///
/// Objetivo de la calibración:
///   ideal-vs-ideal    → 95-100 %   (control)
///   regular-vs-ideal  →  40-60 %   (etiqueta de la experta: 4-6/10)
///
/// Uso:
///   dart run tool/calibrate.dart <landmarks.json>            # tabla actual
///   dart run tool/calibrate.dart <landmarks.json> --sweep    # barrido
///   dart run tool/calibrate.dart <landmarks.json> --csv      # salida CSV
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/dtw_params.dart';
import 'package:bailongo/features/evaluation/engine/dtw_result.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';

/// Nota objetivo de la experta por paso (sobre 10). Ajusta estos valores si la
/// profesora dio notas distintas por paso: el barrido minimiza el error contra
/// ellas, así que son la única "verdad" del proceso.
const Map<String, double> kExpertScore = {
  'basico_adelante_atras': 5,
  'basico_guapeo': 5,
  'cucaracha': 5,
  'suzy_q': 5,
  'right_spot_turn': 5,
  'cumbia_step': 5,
  'cuban_break': 5,
  'giro_punta_talon': 5,
  'kick_flick': 5,
};

/// Banda aceptable para la toma regular (4-6/10 → 40-60 %).
const double kRegularMin = 40;
const double kRegularMax = 60;

/// Mínimo exigible al control ideal-vs-ideal.
const double kIdealMin = 95;

// ─────────────────────────────────────────────────────────────────────────────

/// Reconstruye los vectores de features desde los landmarks planos del JSON.
/// Mismo camino que `VideoPoseProcessor.processFile`: 33 landmarks por
/// fotograma (x, y, z, visibility) → `FeatureExtractor.extractFeatures`.
List<List<double>> featuresFrom(List<dynamic> rawFrames) {
  final out = <List<double>>[];
  for (final fr in rawFrames) {
    final flat = (fr as List).map((e) => (e as num).toDouble()).toList();
    final landmarks = <PoseLandmark>[];
    for (var i = 0; i + 3 < flat.length; i += 4) {
      landmarks.add(PoseLandmark(
        type: i ~/ 4,
        x: flat[i],
        y: flat[i + 1],
        z: flat[i + 2],
        confidence: flat[i + 3],
      ));
    }
    final v = FeatureExtractor.extractFeatures(landmarks);
    if (v != null) out.add(v);
  }
  return out;
}

class StepFrames {
  StepFrames(this.id, this.weights, this.ideal, this.regular);
  final String id;
  final List<double> weights;
  final List<List<double>> ideal;
  final List<List<double>> regular;
}

/// Resultado de evaluar un juego de parámetros sobre todos los pasos.
class SweepOutcome {
  SweepOutcome(this.params, this.rows, {this.perStep = false});
  final DtwParams params;

  /// true cuando cada fila usó los parámetros calibrados de su paso.
  final bool perStep;
  final List<({String id, int ideal, int regular, DtwResult reg})> rows;

  /// Error cuadrático medio contra la nota de la experta, más una penalización
  /// fuerte si el control ideal-vs-ideal se cae (señal de parámetros que
  /// rompen el motor en vez de ajustarlo).
  double get loss {
    var sum = 0.0;
    for (final r in rows) {
      final target = (kExpertScore[r.id] ?? 5) * 10;
      final d = r.regular - target;
      sum += d * d;
      if (r.ideal < kIdealMin) {
        final gap = kIdealMin - r.ideal;
        sum += gap * gap * 4; // el control pesa más que el ajuste fino
      }
    }
    return sum / rows.length;
  }

  int get inBand => rows
      .where((r) => r.regular >= kRegularMin && r.regular <= kRegularMax)
      .length;
}

/// Si `params` es null se usan los parámetros calibrados de cada paso
/// (`step_params.dart`), que es lo que hace la app en producción.
SweepOutcome evaluate(List<StepFrames> data, DtwParams? params) {
  final rows = <({String id, int ideal, int regular, DtwResult reg})>[];
  for (final d in data) {
    final p = params ?? paramsFor(d.id);
    final self =
        DtwComparator.compare(d.ideal, d.ideal, weights: d.weights, params: p);
    final reg =
        DtwComparator.compare(d.regular, d.ideal, weights: d.weights, params: p);
    rows.add((id: d.id, ideal: self.score, regular: reg.score, reg: reg));
  }
  return SweepOutcome(params ?? DtwParams.defaults, rows,
      perStep: params == null);
}

String _worst(DtwResult r) {
  final i = r.worstComponentIndex;
  return (i >= 0 && i < DtwResult.componentNames.length)
      ? DtwResult.componentNames[i]
      : '?';
}

void printTable(SweepOutcome o) {
  stdout.writeln('');
  stdout.writeln(o.perStep
      ? 'parámetros CALIBRADOS POR PASO (step_params.dart) — los de producción'
      : o.params.toString());
  stdout.writeln('');
  stdout.writeln('${'paso'.padRight(24)}${'ideal'.padLeft(6)}'
      '${'reg'.padLeft(6)}${'align'.padLeft(7)}${'ritmo'.padLeft(7)}'
      '${'normCost'.padLeft(10)}  peor componente');
  stdout.writeln('-' * 100);
  for (final r in o.rows) {
    final flag = (r.regular >= kRegularMin && r.regular <= kRegularMax)
        ? ' '
        : '!';
    stdout.writeln('$flag${r.id.padRight(23)}'
        '${r.ideal.toString().padLeft(6)}'
        '${r.regular.toString().padLeft(6)}'
        '${r.reg.alignmentScore.toString().padLeft(7)}'
        '${r.reg.rhythmScore.toString().padLeft(7)}'
        '${r.reg.normalizedCost.toStringAsFixed(3).padLeft(10)}'
        '  ${_worst(r.reg)}');
  }
  stdout.writeln('-' * 100);
  stdout.writeln('en banda 40-60 %: ${o.inBand}/${o.rows.length}'
      '   |   loss: ${o.loss.toStringAsFixed(1)}');
}

void printCsv(SweepOutcome o) {
  stdout.writeln('paso,ideal,regular,align,ritmo,normCost,peor');
  for (final r in o.rows) {
    stdout.writeln('${r.id},${r.ideal},${r.regular},'
        '${r.reg.alignmentScore},${r.reg.rhythmScore},'
        '${r.reg.normalizedCost.toStringAsFixed(4)},"${_worst(r.reg)}"');
  }
}

/// Barrido en rejilla de los parámetros que de verdad mueven la aguja.
/// `alignWeight`/`rhythmWeight` NO se tocan: los fija RNF-06.
void sweep(List<StepFrames> data) {
  final noiseFloors = [0.01, 0.02, 0.03, 0.05, 0.07, 0.09, 0.11];
  final maxes = [0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.70];
  final powers = [0.6, 0.8, 1.0, 1.5, 2.0, 2.5];

  final results = <SweepOutcome>[];
  for (final nf in noiseFloors) {
    for (final mx in maxes) {
      if (mx <= nf + 0.02) continue;
      for (final pw in powers) {
        results.add(evaluate(
          data,
          DtwParams.defaults
              .copyWith(alignNoiseFloor: nf, alignMax: mx, alignCurvePower: pw),
        ));
      }
    }
  }
  results.sort((a, b) => a.loss.compareTo(b.loss));

  stdout.writeln('\n══ BARRIDO: mejores 15 de ${results.length} '
      'combinaciones ══\n');
  stdout.writeln('${'noiseFloor'.padLeft(11)}${'max'.padLeft(7)}'
      '${'power'.padLeft(7)}${'enBanda'.padLeft(9)}${'loss'.padLeft(9)}'
      '   regulares');
  for (final r in results.take(15)) {
    final regs = r.rows.map((e) => e.regular.toString().padLeft(3)).join(' ');
    stdout.writeln(
        '${r.params.alignNoiseFloor.toStringAsFixed(2).padLeft(11)}'
        '${r.params.alignMax.toStringAsFixed(2).padLeft(7)}'
        '${r.params.alignCurvePower.toStringAsFixed(1).padLeft(7)}'
        '${'${r.inBand}/${r.rows.length}'.padLeft(9)}'
        '${r.loss.toStringAsFixed(1).padLeft(9)}   $regs');
  }
  stdout.writeln('\n══ MEJOR JUEGO ══');
  printTable(results.first);
}

/// Estadística por feature sobre todo el corpus: cuánto varía de verdad cada
/// una y cuánto separa la toma regular de la ideal. Sirve para re-derivar
/// `featureRanges`, que venían del prototipo de brazos y no de estos pasos.
void printStats(List<StepFrames> data) {
  const n = FeatureExtractor.featureCount;
  final spread = List<double>.filled(n, 0); // p95-p5 dentro de las ideales
  final sep = List<double>.filled(n, 0); //    |regular - ideal| fotograma a fotograma
  final counted = List<int>.filled(n, 0);

  for (var c = 0; c < n; c++) {
    final all = <double>[];
    var sepSum = 0.0;
    var sepCount = 0;
    for (final d in data) {
      for (final f in d.ideal) {
        if (c < f.length) all.add(f[c]);
      }
      final m = d.ideal.length < d.regular.length
          ? d.ideal.length
          : d.regular.length;
      for (var k = 0; k < m; k++) {
        if (c < d.ideal[k].length && c < d.regular[k].length) {
          sepSum += (d.regular[k][c] - d.ideal[k][c]).abs();
          sepCount++;
        }
      }
    }
    if (all.isEmpty) continue;
    all.sort();
    final p5 = all[(all.length * 0.05).floor()];
    final p95 = all[(all.length * 0.95).floor().clamp(0, all.length - 1)];
    spread[c] = p95 - p5;
    sep[c] = sepCount > 0 ? sepSum / sepCount : 0;
    counted[c] = all.length;
  }

  stdout.writeln('\nESTADÍSTICA POR FEATURE (corpus de los 9 pasos ideales)\n');
  stdout.writeln('${'idx'.padLeft(4)}${'p95-p5'.padLeft(11)}'
      '${'|reg-ideal|'.padLeft(13)}${'rangoActual'.padLeft(13)}'
      '${'sugerido'.padLeft(11)}   componente');
  stdout.writeln('-' * 110);
  final suggested = <double>[];
  for (var c = 0; c < n; c++) {
    final cur = DtwParams.defaultFeatureRanges[c];
    // Rango sugerido = dispersión real de la feature, con suelo para no
    // amplificar ruido en features casi constantes.
    final sug = spread[c] < 1e-6 ? cur : (spread[c] * 2);
    suggested.add(sug);
    stdout.writeln('${c.toString().padLeft(4)}'
        '${spread[c].toStringAsFixed(3).padLeft(11)}'
        '${sep[c].toStringAsFixed(3).padLeft(13)}'
        '${cur.toStringAsFixed(1).padLeft(13)}'
        '${sug.toStringAsFixed(2).padLeft(11)}   '
        '${DtwResult.componentNames[c]}');
  }
  stdout.writeln('\n// featureRanges sugerido:');
  stdout.writeln('  [${suggested.map((e) => e.toStringAsFixed(2)).join(', ')}]');
}

/// Matriz de confusión: cada toma regular contra LOS 9 ideales.
///
/// Valida el motor sin depender de las notas de la experta: si el score más
/// alto de cada regular es contra su propio ideal, el motor reconoce el paso.
/// Se usan pesos uniformes para que las filas sean comparables entre sí.
void printMatrix(List<StepFrames> data) {
  const w = <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      0, 0, 0, 0, 0, 0, 0];
  stdout.writeln('\nMATRIZ: fila = toma regular, columna = ideal contra el '
      'que se compara\n');
  stdout.writeln('${''.padRight(24)}'
      '${data.map((d) => d.id.substring(0, 6).padLeft(7)).join()}'
      '   propio  mejor  ok');
  var hits = 0;
  for (final row in data) {
    final scores = <int>[];
    for (final col in data) {
      scores.add(
          DtwComparator.compare(row.regular, col.ideal, weights: w).score);
    }
    final own = scores[data.indexOf(row)];
    final best = scores.reduce((a, b) => a > b ? a : b);
    final ok = own == best;
    if (ok) hits++;
    stdout.writeln('${row.id.padRight(24)}'
        '${scores.map((e) => e.toString().padLeft(7)).join()}'
        '${own.toString().padLeft(9)}${best.toString().padLeft(7)}'
        '${(ok ? '  SÍ' : '  NO')}');
  }
  stdout.writeln('\nreconoce su propio paso: $hits/${data.length}');
}


/// Ajuste POR PASO: cada paso recibe su propio (alignNoiseFloor, alignMax)
/// para que su toma regular caiga en la nota de la experta.
///
/// Se resuelve por BISECCIÓN sobre `alignMax`, midiendo el score real en cada
/// paso. No se usa la forma cerrada de la curva porque el score final no
/// depende solo de ella: `alignFactor` (cobertura x espejo) multiplica el
/// resultado DESPUÉS, y el ritmo entra con su propio peso. Bisecar sobre la
/// salida real evita depender de esos supuestos.
///
/// `alignNoiseFloor` (la zona muerta de "esto ya es perfecto") NO se puede
/// derivar de los datos: haría falta una toma BUENA-PERO-NO-IDEAL por paso, y
/// solo hay una ideal y una regular. Se fija como fracción del coste regular:
/// una ejecución `1/kNoiseFloorFrac` veces más cercana que la toma de 5/10
/// puntúa 100. Es una heurística declarada, no un valor medido.
const double kNoiseFloorFrac = 0.25;

/// Busca el `alignMax` que lleva la toma regular a `target`.
({double max, int score, bool exact}) _fitMax(
    StepFrames d, double nf, double target) {
  DtwParams at(double mx) => DtwParams.defaults
      .copyWith(alignNoiseFloor: nf, alignMax: mx, alignCurvePower: 2.0);
  int scoreAt(double mx) =>
      DtwComparator.compare(d.regular, d.ideal, weights: d.weights, params: at(mx))
          .score;

  var lo = nf * 1.001;
  var hi = math.max(nf * 200, 5.0);
  // El score crece con alignMax (más tolerante). Si ni el techo alcanza el
  // objetivo, el límite lo impone la cobertura/espejo, no la curva.
  if (scoreAt(hi) < target) {
    return (max: hi, score: scoreAt(hi), exact: false);
  }
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (scoreAt(mid) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (max: hi, score: scoreAt(hi), exact: true);
}

void printFit(List<StepFrames> data) {
  stdout.writeln('\nAJUSTE POR PASO (objetivo = nota de la experta)\n');
  stdout.writeln('${'paso'.padRight(24)}${'costeReg'.padLeft(10)}'
      '${'ritmo'.padLeft(7)}${'noiseFloor'.padLeft(12)}${'max'.padLeft(10)}'
      '${'regular'.padLeft(9)}${'ideal'.padLeft(7)}   nota');
  stdout.writeln('-' * 88);

  final emitted = <String>[];
  for (final d in data) {
    final base = DtwComparator.compare(d.regular, d.ideal, weights: d.weights);
    final target = (kExpertScore[d.id] ?? 5) * 10;
    final nf = base.normalizedCost * kNoiseFloorFrac;
    final fit = _fitMax(d, nf, target);

    final tuned = DtwParams.defaults
        .copyWith(alignNoiseFloor: nf, alignMax: fit.max, alignCurvePower: 2.0);
    final self = DtwComparator.compare(d.ideal, d.ideal,
        weights: d.weights, params: tuned);

    stdout.writeln('${d.id.padRight(24)}'
        '${base.normalizedCost.toStringAsFixed(4).padLeft(10)}'
        '${base.rhythmScore.toString().padLeft(7)}'
        '${nf.toStringAsFixed(4).padLeft(12)}'
        '${fit.max.toStringAsFixed(4).padLeft(10)}'
        '${fit.score.toString().padLeft(9)}'
        '${self.score.toString().padLeft(7)}'
        '   ${fit.exact ? "ok" : "TECHO: no alcanza el objetivo"}');

    emitted.add("  '${d.id}': DtwParams(\n"
        "    alignNoiseFloor: ${nf.toStringAsFixed(4)},\n"
        "    alignMax: ${fit.max.toStringAsFixed(4)},\n"
        "  ),");
  }

  stdout.writeln('\n// pegar en lib/features/evaluation/engine/step_params.dart');
  stdout.writeln('const Map<String, DtwParams> kStepParams = {');
  for (final e in emitted) {
    stdout.writeln(e);
  }
  stdout.writeln('};');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('uso: dart run tool/calibrate.dart <landmarks.json> '
        '[--sweep|--csv]');
    exitCode = 64;
    return;
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('no existe ${args.first}. Genera el JSON antes con:');
    stderr.writeln('  python tool/extract_landmarks.py <salida.json> '
        'assets/videos/*.mp4 assets/fixtures/*_regular.mp4');
    exitCode = 66;
    return;
  }

  final uniform = args.contains('--uniform');
  final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

  final data = <StepFrames>[];
  final missing = <String>[];
  for (final id in kRealStepIds) {
    final idealRaw = raw[id] as Map<String, dynamic>?;
    final regRaw = raw['${id}_regular'] as Map<String, dynamic>?;
    if (idealRaw == null || regRaw == null) {
      missing.add(id);
      continue;
    }
    final ideal = featuresFrom(idealRaw['frames'] as List);
    final regular = featuresFrom(regRaw['frames'] as List);
    if (ideal.isEmpty || regular.isEmpty) {
      stderr.writeln('!! $id: sin fotogramas con features válidas '
          '(ideal ${ideal.length}, regular ${regular.length})');
      continue;
    }
    // Verificación de implementar_pasos.txt §3: de los instantes muestreados
    // (los que Android también visitaría), cuántos dan features válidas. Un
    // desplome aquí significa que el tren inferior se sale de cuadro y la
    // ventana de captura se desincroniza.
    final checks = [
      (name: id, raw: idealRaw, feats: ideal),
      (name: '${id}_regular', raw: regRaw, feats: regular),
    ];
    for (final e in checks) {
      final sampled = (e.raw['sampled'] as num?)?.toInt() ?? 0;
      final pct = sampled > 0 ? e.feats.length * 100 ~/ sampled : 0;
      if (pct < 90) {
        stderr.writeln('!! ${e.name}: solo $pct % de los instantes dan '
            'features válidas (${e.feats.length}/$sampled)');
      }
    }
    // --uniform: ignora los vectores por paso y pondera todo el tren inferior
    // por igual. Sirve para aislar si los pesos elegidos a mano ayudan o
    // estorban, ya que nunca fueron validados contra datos.
    // --stale: simula lo que hay HOY en Firestore, sembrado antes de añadir
    // tren superior y cadera: vector de 22 con brazos/hombros a 0. El
    // comparador rellena las 4 de cadera que faltan con 1.0.
    final stale = args.contains('--stale');
    final base = kStepWeights[id]!;
    final w = stale
        ? [
            ...base.sublist(0, 15),
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // 15-21 como se sembraron
          ]
        : uniform
        ? const <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            0, 0, 0, 0, 0, 0, 0]
        : kStepWeights[id]!;
    data.add(StepFrames(id, w.cast<double>(), ideal, regular));
  }

  if (missing.isNotEmpty) {
    stderr.writeln('faltan en el JSON: ${missing.join(', ')}');
  }
  if (data.isEmpty) {
    stderr.writeln('nada que calibrar.');
    exitCode = 65;
    return;
  }

  if (args.contains('--fit')) {
    printFit(data);
  } else if (args.contains('--matrix')) {
    printMatrix(data);
  } else if (args.contains('--stats')) {
    printStats(data);
  } else if (args.contains('--csv')) {
    printCsv(evaluate(data, DtwParams.defaults));
  } else if (args.contains('--sweep')) {
    printTable(evaluate(data, DtwParams.defaults));
    sweep(data);
  } else if (args.contains('--global')) {
    printTable(evaluate(data, DtwParams.defaults));
  } else {
    // Por defecto: exactamente lo que corre la app (parámetros por paso).
    printTable(evaluate(data, null));
  }
}
