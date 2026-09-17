/// Banco de ESCENARIOS del motor de evaluación (implementar_pasos.txt §7-quater).
///
/// `calibrate.dart` solo tenía dos puntos por paso (ideal contra sí mismo y la
/// toma de 5/10). Con eso la escala quedaba sin forma y sin controles: se
/// aprobaba al que se quedaba quieto y se castigaba al que bailaba bien pero
/// con otra cámara. Este banco genera, a partir de los landmarks REALES de las
/// dos tomas de la profesora, los casos que aparecen en uso:
///
///   bueno_vivo      toma de 10 con ruido de cámara, otra proporción corporal,
///                   cámara 480x720, retraso de reacción y fps irregulares
///   malo / malo_vivo  toma de 5 (etiqueta de la experta)
///   mezcla75        75 % buena + 25 % mala (≈ 7.5/10)
///   quieto          se queda parado todo el intento
///   quieto_mitad    baila la primera mitad y se para (bug reportado: 99 %)
///   quieto_final    se para en el último cuarto
///   arranca_tarde   espera 1/3 del intento y luego baila en su sitio
///   otro_paso       baila un paso distinto del catálogo
///   espejo          ejecuta con la lateralidad invertida
///   lento           va 10 % más lento que la música
///
/// Uso:
///   dart run tool/bench.dart tool/landmarks.json            # tabla
///   dart run tool/bench.dart tool/landmarks.json --detail   # por paso
///   dart run tool/bench.dart tool/landmarks.json --fit      # floor/max por paso
///   dart run tool/bench.dart tool/landmarks.json --sweep    # barrido global
///   dart run tool/bench.dart tool/landmarks.json --ranges   # rangos por feature
///   dart run tool/bench.dart tool/landmarks.json --snr      # tabla de temblor
///   dart run tool/bench.dart tool/landmarks.json --legacy   # pipeline anterior
///   --step=<pasoId> limita a un paso
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

/// Geometría de las tomas de la profesora (720x1280) y de la cámara en vivo
/// (ResolutionPreset.medium en Android: 720x480 girado a vertical).
const double kVideoW = 720, kVideoH = 1280;
const double kLiveW = 480, kLiveH = 720;

typedef Lm = List<double>; // 33 x 4 planos: x, y, z, visibility

class Take {
  Take(this.frames);
  final List<Lm> frames;

  /// Pose en el instante [ms] (interpolación lineal; fuera de rango se congela).
  Lm at(double ms) {
    final pos = ms / 33.0;
    if (pos <= 0) return frames.first;
    if (pos >= frames.length - 1) return frames.last;
    final i = pos.floor();
    final t = pos - i;
    final a = frames[i], b = frames[i + 1];
    return List<double>.generate(a.length, (k) => a[k] + (b[k] - a[k]) * t);
  }

  double get durationMs => frames.length * 33.0;
}

/// Una captura simulada: landmarks con su instante y la relación de aspecto
/// de la imagen de la que salieron.
class Capture {
  Capture(this.frames, this.timesMs, this.aspect);
  final List<Lm> frames;
  final List<int> timesMs;
  final double aspect; // alto / ancho
}

/// Condiciones de la cámara del alumno: ruido del modelo lite en vivo,
/// encuadre, inclinación, proporciones del cuerpo, fps y reacción.
class LiveConditions {
  LiveConditions(math.Random rng, {double noiseMul = 1})
      // Temblor medido en las tomas (residuo de alta frecuencia en guapeo, el
      // paso más lento): ~0.006 de la anchura de cadera. En vivo, con menos
      // resolución y desenfoque, se asume ~3x: 0.0025 normalizado en cámara.
      : noiseJoint = 0.0025 * noiseMul,
        noiseFoot = 0.005 * noiseMul,
        rotationRad = (rng.nextDouble() * 2 - 1) * 3 * math.pi / 180,
        bodySx = 0.92 + rng.nextDouble() * 0.16,
        bodySy = 0.95 + rng.nextDouble() * 0.10,
        zoom = 0.85 + rng.nextDouble() * 0.2,
        lagMs = 100 + rng.nextDouble() * 200,
        tempo = 0.98 + rng.nextDouble() * 0.04;

  final double noiseJoint, noiseFoot;
  final double rotationRad, bodySx, bodySy, zoom, lagMs, tempo;
}

/// Pasa la pose de la toma (normalizada sobre 720x1280) a la imagen de la
/// cámara en vivo (normalizada sobre 480x720) aplicando cuerpo, zoom e
/// inclinación, más ruido AR(1) (el temblor del modelo es correlacionado).
class LiveCamera {
  LiveCamera(this.c, this.rng);
  final LiveConditions c;
  final math.Random rng;
  final List<double> _nx = List.filled(33, 0), _ny = List.filled(33, 0);

  double _gauss() {
    final u1 = rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  Lm project(Lm src) {
    final out = List<double>.from(src);
    final hx = (src[23 * 4] + src[24 * 4]) / 2 * kVideoW;
    final hy = (src[23 * 4 + 1] + src[24 * 4 + 1]) / 2 * kVideoH;
    final cosR = math.cos(c.rotationRad), sinR = math.sin(c.rotationRad);
    // El cuerpo ocupa en la cámara en vivo una altura parecida (zoom ~1).
    final scale = c.zoom * kLiveH / kVideoH;
    for (var i = 0; i < 33; i++) {
      var px = src[i * 4] * kVideoW - hx;
      var py = src[i * 4 + 1] * kVideoH - hy;
      px *= c.bodySx;
      py *= c.bodySy;
      final rx = px * cosR - py * sinR;
      final ry = px * sinR + py * cosR;
      final foot = i >= 27;
      final sigma = foot ? c.noiseFoot : c.noiseJoint;
      _nx[i] = 0.6 * _nx[i] + 0.8 * sigma * _gauss();
      _ny[i] = 0.6 * _ny[i] + 0.8 * sigma * _gauss();
      out[i * 4] = 0.5 + rx * scale / kLiveW + _nx[i];
      out[i * 4 + 1] = 0.55 + ry * scale / kLiveH + _ny[i];
    }
    return out;
  }
}

/// Instantes en los que la app obtiene pose en vivo: el detector no llega a
/// 30 fps y se salta fotogramas (`_busy`), con jitter.
List<int> liveTimes(double durationMs, math.Random rng) {
  final out = <int>[];
  var t = 10.0 + rng.nextDouble() * 20;
  while (t < durationMs) {
    out.add(t.round());
    t += (rng.nextDouble() < 0.45 ? 66 : 33) + (rng.nextDouble() * 10 - 5);
  }
  return out;
}

/// Espejo de imagen: x -> 1-x e intercambio de landmarks izquierda/derecha.
Lm mirrorLm(Lm src) {
  const pairs = [
    [1, 4], [2, 5], [3, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16],
    [17, 18], [19, 20], [21, 22], [23, 24], [25, 26], [27, 28], [29, 30],
    [31, 32],
  ];
  final out = List<double>.from(src);
  for (var i = 0; i < 33; i++) {
    out[i * 4] = 1 - src[i * 4];
  }
  for (final p in pairs) {
    for (var k = 0; k < 4; k++) {
      final a = p[0] * 4 + k, b = p[1] * 4 + k;
      final tmp = out[a];
      out[a] = out[b];
      out[b] = tmp;
    }
  }
  return out;
}

Lm lerpLm(Lm a, Lm b, double t) =>
    List<double>.generate(a.length, (k) => a[k] + (b[k] - a[k]) * t);

/// Qué hace el "alumno" en el instante t (ms desde el ¡YA!) → pose en
/// coordenadas de la toma original.
typedef Performer = Lm Function(double tMs);

Capture perform(Performer who, double durationMs, math.Random rng,
    {required bool live, double noiseMul = 1}) {
  if (!live) {
    final frames = <Lm>[];
    final times = <int>[];
    for (var t = 0.0; t < durationMs; t += 33) {
      frames.add(who(t));
      times.add(t.round());
    }
    return Capture(frames, times, kVideoH / kVideoW);
  }
  final cond = LiveConditions(rng, noiseMul: noiseMul);
  final cam = LiveCamera(cond, rng);
  final times = liveTimes(durationMs, rng);
  final frames = [
    for (final t in times) cam.project(who((t - cond.lagMs) * cond.tempo)),
  ];
  return Capture(frames, times, kLiveH / kLiveW);
}

/// Features de una captura con corrección de aspecto, remuestreadas a la
/// rejilla de 33 ms de la referencia (lo mismo que hace la app).
/// --legacy: reproduce la app ANTES de esta revisión (sin corrección de
/// aspecto y sin remuestreo), para medir el punto de partida.
bool legacy = false;

List<List<double>> featuresOf(Capture c, double durationMs) {
  final feats = <List<double>>[];
  final times = <int>[];
  for (var i = 0; i < c.frames.length; i++) {
    final v = FeatureExtractor.extractFeatures(toLandmarks(c.frames[i]),
        aspectRatio: legacy ? 1.0 : c.aspect);
    if (v != null) {
      feats.add(v);
      times.add(c.timesMs[i]);
    }
  }
  if (legacy) return feats;
  return FrameResampler.toGrid(feats, times, durationMs: durationMs.round());
}

List<PoseLandmark> toLandmarks(Lm flat) => [
      for (var i = 0; i + 3 < flat.length; i += 4)
        PoseLandmark(
          type: i ~/ 4,
          x: flat[i],
          y: flat[i + 1],
          z: flat[i + 2],
          confidence: flat[i + 3],
        ),
    ];

class Scenario {
  const Scenario(this.name, this.target, this.tol, {this.weight = 1});
  final String name;

  /// Nota esperada (0-100) y tolerancia sin castigo alrededor.
  final double target, tol;
  final double weight;
}

const scenarios = <Scenario>[
  Scenario('bueno_vivo', 95, 7, weight: 1),
  // Pruebas reales (2026-09-17): bailando bien, alineación 0 en guapeo, suzy_q
  // y right_spot_turn con ritmo alto. El "bueno" de arriba es la PROPIA toma
  // de la profesora: mismos brazos, misma amplitud, mismo fraseo. Un alumno
  // que lo hace bien difiere justo en eso. Este escenario es el que manda.
  Scenario('alumno_bien', 85, 8, weight: 4),
  Scenario('malo', 50, 6, weight: 2),
  Scenario('malo_vivo', 48, 8, weight: 2),
  Scenario('mezcla75', 75, 10),
  Scenario('quieto', 0, 8, weight: 3),
  Scenario('quieto_mitad', 30, 18, weight: 3),
  Scenario('quieto_final', 62, 13),
  Scenario('arranca_tarde', 50, 20),
  Scenario('otro_paso', 15, 25),
  Scenario('espejo', 15, 20),
  Scenario('lento', 60, 20),
];

class StepData {
  StepData(this.id, this.good, this.bad, this.others);
  final String id;
  final Take good, bad;
  final List<Take> others;
}

Performer performerFor(String name, StepData d, math.Random rng) {
  final g = d.good, b = d.bad;
  final dur = g.durationMs;
  // La toma mala puede durar distinto: se estira al tiempo de la buena.
  Lm badAt(double t) => b.at(t * b.durationMs / dur);
  switch (name) {
    case 'bueno_vivo':
      return g.at;
    case 'alumno_bien':
      return studentPerformer(d, rng);
    case 'malo':
    case 'malo_vivo':
      // A su propio tempo: la toma mala dura distinto en giro y kick flick.
      return b.at;
    case 'mezcla75':
      return (t) => lerpLm(g.at(t), badAt(t), 0.25);
    case 'quieto':
      return (_) => g.frames.first;
    case 'quieto_mitad':
      return (t) => g.at(math.min(t, dur * 0.5));
    case 'quieto_final':
      return (t) => g.at(math.min(t, dur * 0.75));
    case 'arranca_tarde':
      return (t) => t < dur / 3 ? g.frames.first : g.at(t);
    case 'otro_paso':
      final o = d.others[rng.nextInt(d.others.length)];
      return (t) => o.at(t % o.durationMs);
    case 'espejo':
      return (t) => mirrorLm(g.at(t));
    case 'lento':
      return (t) => g.at(t * 0.9);
  }
  throw ArgumentError(name);
}

/// Alumno que baila BIEN el paso, pero no es la profesora:
///   - brazos a su manera: los codos y muñecas siguen los hombros del paso,
///     pero con el braceo de otra toma (otro paso) de la profesora
///   - amplitud propia: todo el movimiento respecto a su postura media
///     escalado entre 0.75 y 1.2
///   - fraseo propio: retraso de 150-400 ms y adelantos/atrasos suaves de
///     ±120 ms a lo largo del intento
Performer studentPerformer(StepData d, math.Random rng) {
  final g = d.good;
  final armsFrom = d.others[rng.nextInt(d.others.length)];
  final amp = 0.75 + rng.nextDouble() * 0.45;
  final lag = 150 + rng.nextDouble() * 250;
  final wobblePeriod = 3000 + rng.nextDouble() * 3000;
  final wobblePhase = rng.nextDouble() * 2 * math.pi;

  // Postura media relativa al centro de cadera (para escalar la amplitud).
  final mean = List<double>.filled(132, 0);
  for (final f in g.frames) {
    final hx = (f[92] + f[96]) / 2, hy = (f[93] + f[97]) / 2;
    for (var i = 0; i < 33; i++) {
      mean[i * 4] += f[i * 4] - hx;
      mean[i * 4 + 1] += f[i * 4 + 1] - hy;
    }
  }
  for (var k = 0; k < 132; k++) {
    mean[k] /= g.frames.length;
  }

  return (t) {
    final tt = t - lag + 120 * math.sin(2 * math.pi * t / wobblePeriod + wobblePhase);
    final src = g.at(tt);
    final out = List<double>.from(src);
    final hx = (src[92] + src[96]) / 2, hy = (src[93] + src[97]) / 2;
    for (var i = 0; i < 33; i++) {
      for (var c = 0; c < 2; c++) {
        final center = c == 0 ? hx : hy;
        final rel = src[i * 4 + c] - center;
        out[i * 4 + c] = center + mean[i * 4 + c] + (rel - mean[i * 4 + c]) * amp;
      }
    }
    // Brazos de otra toma, pegados a los hombros de esta.
    final other = armsFrom.at(tt % armsFrom.durationMs);
    for (final pair in const [[11, 13], [11, 15], [12, 14], [12, 16]]) {
      final sh = pair[0], j = pair[1];
      for (var c = 0; c < 2; c++) {
        out[j * 4 + c] = out[sh * 4 + c] + (other[j * 4 + c] - other[sh * 4 + c]);
      }
      out[j * 4 + 3] = other[j * 4 + 3];
    }
    return out;
  };
}

class Row {
  Row(this.step, this.scenario, this.result);
  final String step;
  final Scenario scenario;
  final DtwResult result;
}

/// Un intento simulado ya convertido a features: no depende de los parámetros
/// del motor, así que se genera una vez y se puntúa muchas.
class Case {
  Case(this.step, this.scenario, this.user, this.ref);
  final String step;
  final Scenario scenario;
  final List<List<double>> user, ref;
}

/// Cuántas repeticiones aleatorias se promedian por escenario "vivo".
const int kSeeds = 3;

List<Case> buildCases(List<StepData> data, {Set<String>? only}) {
  final cases = <Case>[];
  for (final d in data) {
    final dur = d.good.durationMs;
    final ref = featuresOf(
        perform(d.good.at, dur, math.Random(0), live: false), dur);
    for (final s in scenarios) {
      if (only != null && !only.contains(s.name)) continue;
      final live = s.name != 'malo';
      final seeds = live ? kSeeds : 1;
      for (var k = 0; k < seeds; k++) {
        final rng = math.Random(1000 * k + s.name.hashCode % 997);
        final who = performerFor(s.name, d, rng);
        final user = featuresOf(
            perform(who, dur, rng,
                live: live, noiseMul: s.name == 'alumno_bien' ? 1.5 : 1),
            dur);
        cases.add(Case(d.id, s, user, ref));
      }
    }
  }
  return cases;
}

typedef ParamsFor = DtwParams Function(String stepId);

List<Row> score(List<Case> cases, ParamsFor paramsOf) => [
      for (final c in cases)
        Row(
          c.step,
          c.scenario,
          DtwComparator.compare(c.user, c.ref,
              weights: kStepWeights[c.step], params: paramsOf(c.step)),
        ),
    ];

double lossOf(List<Row> rows) {
  var sum = 0.0, wsum = 0.0;
  for (final r in rows) {
    final err = (r.result.score - r.scenario.target).abs() - r.scenario.tol;
    if (err > 0) sum += r.scenario.weight * err * err;
    wsum += r.scenario.weight;
  }
  return sum / wsum;
}

void printSummary(List<Row> rows, {bool detail = false}) {
  final steps = <String>[];
  for (final r in rows) {
    if (!steps.contains(r.step)) steps.add(r.step);
  }
  final names = scenarios.map((s) => s.name).toList();
  String cell(String step, String sc) {
    final rs = rows.where((r) => r.step == step && r.scenario.name == sc);
    if (rs.isEmpty) return '   -';
    final avg = rs.map((r) => r.result.score).reduce((a, b) => a + b) / rs.length;
    final s = rs.first.scenario;
    final ok = (avg - s.target).abs() <= s.tol;
    return '${avg.round().toString().padLeft(4)}${ok ? ' ' : '!'}';
  }

  stdout.writeln('');
  stdout.writeln('paso'.padRight(22) +
      names.map((n) => n.substring(0, math.min(9, n.length)).padLeft(10)).join());
  stdout.writeln('objetivo'.padRight(22) +
      scenarios
          .map((s) => '${s.target.round()}±${s.tol.round()}'.padLeft(10))
          .join());
  stdout.writeln('-' * (22 + 10 * names.length));
  for (final st in steps) {
    stdout.writeln(st.padRight(22) +
        names.map((n) => cell(st, n).padLeft(10)).join());
  }
  stdout.writeln('-' * (22 + 10 * names.length));
  stdout.writeln('loss ${lossOf(rows).toStringAsFixed(1)}');

  if (detail) {
    stdout.writeln('\nDETALLE (media de semillas): total = align / ritmo');
    for (final st in steps) {
      stdout.writeln(st);
      for (final n in names) {
        final rs = rows.where((r) => r.step == st && r.scenario.name == n).toList();
        if (rs.isEmpty) continue;
        double m(int Function(DtwResult) f) =>
            rs.map((r) => f(r.result)).reduce((a, b) => a + b) / rs.length;
        stdout.writeln('  ${n.padRight(15)} ${m((r) => r.score).round().toString().padLeft(3)}'
            ' = ${m((r) => r.alignmentScore).round().toString().padLeft(3)}'
            ' / ${m((r) => r.rhythmScore).round().toString().padLeft(3)}'
            '   rel ${(rs.map((r) => r.result.relativeCost).reduce((a, b) => a + b) / rs.length).toStringAsFixed(2)}'
            ' cov ${(rs.map((r) => r.result.coverage).reduce((a, b) => a + b) / rs.length).toStringAsFixed(2)}'
            ' mir ${(rs.map((r) => r.result.mirrorFactor).reduce((a, b) => a + b) / rs.length).toStringAsFixed(2)}'
            '   seg ${rs.first.result.segmentScore}');
      }
    }
  }
}

Future<Map<String, StepData>> loadData(String path) async {
  final raw = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  List<Lm> framesOf(String key) => [
        for (final f in (raw[key] as Map<String, dynamic>)['frames'] as List)
          (f as List).map((e) => (e as num).toDouble()).toList(),
      ];
  final goods = {for (final id in kRealStepIds) id: Take(framesOf(id))};
  return {
    for (final id in kRealStepIds)
      id: StepData(
        id,
        goods[id]!,
        Take(framesOf('${id}_regular')),
        [for (final o in kRealStepIds) if (o != id) goods[o]!],
      ),
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('uso: dart run tool/bench.dart <landmarks.json> [--detail]');
    exitCode = 64;
    return;
  }
  legacy = args.contains('--legacy');
  final data = (await loadData(args.first)).values.toList();
  final stepArg = args.where((a) => a.startsWith('--step=')).toList();
  final selected = stepArg.isEmpty
      ? data
      : data.where((d) => d.id == stepArg.first.substring(7)).toList();
  final sw = Stopwatch()..start();
  final cases = buildCases(selected);
  stdout.writeln('casos: ${cases.length} (${sw.elapsedMilliseconds} ms)');
  sw.reset();
  // --amp / --clip=x / --nf=x / --max=x: prueban variantes sin tocar lib/.
  double? num(String flag) {
    final a = args.where((e) => e.startsWith('--$flag=')).toList();
    return a.isEmpty ? null : double.parse(a.first.split('=')[1]);
  }
  final base = DtwParams.defaults.copyWith(
    amplitudeNormalize: args.contains('--amp') ? true : null,
    featureClip: num('clip'),
    alignNoiseFloor: num('nf'),
    alignMax: num('max'),
    alignCurvePower: num('pow'),
  );
  if (args.contains('--groups')) {
    printGroups(cases, base);
    return;
  }
  if (args.contains('--fit')) {
    fitPerStep(cases, base);
    return;
  }
  if (args.contains('--ranges')) {
    printRanges(cases);
    return;
  }
  if (args.contains('--snr')) {
    printSnr(cases, perFeature: args.contains('--detail'));
    return;
  }
  if (args.contains('--sweep')) {
    sweep(cases, base);
    return;
  }
  final global = args.contains('--global') || base != DtwParams.defaults;
  final rows = score(cases, global ? (_) => base : paramsFor);
  printSummary(rows, detail: args.contains('--detail'));
  stdout.writeln('(${sw.elapsedMilliseconds} ms) ${paramsFor(selected.first.id)}');
}

/// Barrido por coordenadas: mueve un parámetro cada vez y se queda con el que
/// baja la pérdida. Repite hasta que nada mejora.
void sweep(List<Case> cases, DtwParams start) {
  var best = start;
  var bestLoss = lossOf(score(cases, (_) => best));
  stdout.writeln('inicio loss ${bestLoss.toStringAsFixed(1)}');
  final axes = <String, List<DtwParams Function(DtwParams)>>{
    'nf': [for (final v in [0.1, 0.2, 0.3, 0.4, 0.5]) (p) => p.copyWith(alignNoiseFloor: v)],
    'max': [for (final v in [1.0, 1.2, 1.4, 1.6, 1.8, 2.0]) (p) => p.copyWith(alignMax: v)],
    'pow': [for (final v in [0.6, 0.8, 1.0, 1.25, 1.5]) (p) => p.copyWith(alignCurvePower: v)],
    'clip': [for (final v in [1.5, 2.0, 3.0, 4.0, 6.0]) (p) => p.copyWith(featureClip: v)],
    'off': [for (final v in [0.0, 0.1, 0.25, 0.5, 1.0]) (p) => p.copyWith(offsetWeight: v)],
    'covZ': [for (final v in [0.05, 0.1, 0.15, 0.2, 0.3]) (p) => p.copyWith(coverageZeroRatio: v)],
    'covF': [for (final v in [0.35, 0.4, 0.5, 0.6, 0.7]) (p) => p.copyWith(coverageFullRatio: v)],
    'covMin': [for (final v in [0.0, 0.2, 0.4]) (p) => p.copyWith(coverageMinFactor: v)],
    'rhyZ': [for (final v in [0.0, 0.1, 0.2, 0.3]) (p) => p.copyWith(rhythmCorrZero: v)],
    'rhyF': [for (final v in [0.3, 0.4, 0.5, 0.6]) (p) => p.copyWith(rhythmCorrFull: v)],
    'k': [for (final v in [1.0, 2.0, 4.0, 8.0, 16.0]) (p) => p.copyWith(snrK: v)],
    'ampN': [for (final v in [1.0, 2.0, 3.0, 4.0]) (p) => p.copyWith(amplitudeNoiseMul: v)],
  };
  for (var round = 0; round < 3; round++) {
    var improved = false;
    for (final e in axes.entries) {
      for (final f in e.value) {
        final cand = f(best);
        final l = lossOf(score(cases, (_) => cand));
        if (l < bestLoss - 1e-6) {
          bestLoss = l;
          best = cand;
          improved = true;
          stdout.writeln('  ${e.key.padRight(6)} -> loss ${l.toStringAsFixed(1)}  $best');
        }
      }
    }
    if (!improved) break;
  }
  printSummary(score(cases, (_) => best), detail: false);
  stdout.writeln(best);
}

/// --snr: amplitud del modelo frente al temblor en vivo, por feature (unidades
/// de rango, tras suavizar). Una feature cuyo movimiento en la referencia no
/// supera el temblor solo añade ruido al coste.
void printSnr(List<Case> cases, {bool perFeature = false}) {
  double stdOf(List<List<double>> f, int c, int win) {
    // media de la desviación en ventanas de `win` fotogramas
    var acc = 0.0;
    var k = 0;
    for (var s = 0; s + win <= f.length; s += win) {
      var mean = 0.0;
      for (var t = s; t < s + win; t++) {
        mean += f[t][c];
      }
      mean /= win;
      var v = 0.0;
      for (var t = s; t < s + win; t++) {
        v += (f[t][c] - mean) * (f[t][c] - mean);
      }
      acc += math.sqrt(v / win);
      k++;
    }
    return k > 0 ? acc / k : 0;
  }

  List<List<double>> prep(List<List<double>> f) {
    const r = DtwParams.defaultFeatureRanges;
    final sc = [for (final x in f) List<double>.generate(x.length, (c) => x[c] / r[c])];
    const half = 2;
    return List.generate(sc.length, (i) {
      final a = math.max(0, i - half), b = math.min(sc.length, i + half + 1);
      return List<double>.generate(sc[0].length, (c) {
        var s = 0.0;
        for (var t = a; t < b; t++) {
          s += sc[t][c];
        }
        return s / (b - a);
      });
    });
  }

  final steps = cases.map((c) => c.step).toSet();
  final noiseSum = List<double>.filled(FeatureExtractor.featureCount, 0);
  var noiseN = 0;
  for (final c in cases.where((c) => c.scenario.name == 'quieto')) {
    final u = prep(c.user);
    for (var f = 0; f < FeatureExtractor.featureCount; f++) {
      noiseSum[f] += stdOf(u, f, 30);
    }
    noiseN++;
  }
  stdout.writeln('// temblor en vivo por feature (media de $noiseN casos quieto):');
  stdout.writeln('[${noiseSum.map((e) => (e / noiseN).toStringAsFixed(4)).join(', ')}]');
  if (!perFeature) return;
  for (final st in steps) {
    final still = cases.firstWhere((c) => c.step == st && c.scenario.name == 'quieto');
    final good = cases.where((c) => c.step == st && c.scenario.name == 'bueno_vivo').first;
    final bad = cases.firstWhere((c) => c.step == st && c.scenario.name == 'malo');
    final r = prep(still.ref), u = prep(still.user), g = prep(good.user), b = prep(bad.user);
    stdout.writeln('\n$st   (ampRef / ruidoQuieto / ampBuenoVivo / ampMalo   peso)');
    final w = kStepWeights[st]!;
    for (var c = 0; c < FeatureExtractor.featureCount; c++) {
      final ar = stdOf(r, c, 30), an = stdOf(u, c, 30), ag = stdOf(g, c, 30), ab = stdOf(b, c, 30);
      stdout.writeln('  ${c.toString().padLeft(2)} ${ar.toStringAsFixed(3).padLeft(7)} ${an.toStringAsFixed(3).padLeft(7)} '
          '${ag.toStringAsFixed(3).padLeft(7)} ${ab.toStringAsFixed(3).padLeft(7)}  snr ${(ar / math.max(an, 1e-6)).toStringAsFixed(1).padLeft(5)}  w ${w[c]}');
    }
  }
}

/// --ranges: re-deriva `DtwParams.defaultFeatureRanges` (2 x (p95 - p5) de
/// cada feature sobre las 9 tomas ideales) con el pipeline actual, que corrige
/// el aspecto: los rangos anteriores se midieron sin esa corrección.
void printRanges(List<Case> cases) {
  final refs = <String, List<List<double>>>{};
  for (final c in cases) {
    refs[c.step] = c.ref;
  }
  final out = <String>[];
  for (var f = 0; f < FeatureExtractor.featureCount; f++) {
    final xs = [for (final r in refs.values) for (final fr in r) fr[f]]..sort();
    final p5 = xs[(xs.length * 0.05).floor()];
    final p95 = xs[(xs.length * 0.95).floor()];
    final range = 2 * (p95 - p5);
    out.add('    ${range.toStringAsFixed(range >= 10 ? 2 : 3)}, // $f  '
        '${DtwResult.componentNames[f]}  (antes ${DtwParams.defaultFeatureRanges[f]})');
  }
  stdout.writeln(out.join('\n'));
}

/// --fit: ajuste POR PASO de los dos extremos de la curva de alineación.
///   `alignMax`        se resuelve para que la toma de 5/10 de la profesora
///                     (limpia y en vivo) dé 50 %: la etiqueta real manda.
///   `alignNoiseFloor` se recorre de menor a mayor y se elige el PRIMERO con
///                     el que el alumno que baila bien (alumno_bien) llega a
///                     [kGoodTarget]; si ninguno llega, el que más se acerca.
///                     Nunca más flexible de lo necesario.
/// Restricciones: quedarse quieto desde la mitad no puede pasar de
/// [kHalfStillMax] y la curva conserva un tramo mínimo (max - floor ≥ 0.25).
const double kFitMin = 0.9, kFitMax = 2.2;
const double kGoodTarget = 85;
const double kHalfStillMax = 55;
const floors = [0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.7];

void fitPerStep(List<Case> cases, DtwParams global) {
  final fitted = <String, DtwParams>{};
  final steps = <String>[];
  for (final c in cases) {
    if (!steps.contains(c.step)) steps.add(c.step);
  }
  double avgScore(String step, Set<String> names, DtwParams p) {
    final rs = score(
        cases
            .where((c) => c.step == step && names.contains(c.scenario.name))
            .toList(),
        (_) => p);
    var total = 0.0;
    for (final n in names) {
      final xs = rs.where((r) => r.scenario.name == n).map((r) => r.result.score);
      total += xs.reduce((a, b) => a + b) / xs.length;
    }
    return total / names.length;
  }

  /// Bisección de un parámetro monótono creciente en la nota.
  double solve(double lo, double hi, double target, double Function(double) f) {
    if (f(lo) >= target) return lo;
    if (f(hi) <= target) return hi;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      if (f(mid) < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  for (final st in steps) {
    DtwParams? best;
    var bestGood = -1.0;
    for (final floor in floors) {
      var p = global.copyWith(alignNoiseFloor: floor);
      final max = solve(math.max(kFitMin, floor + 0.25), kFitMax, 50,
          (v) => avgScore(st, {'malo', 'malo_vivo'}, p.copyWith(alignMax: v)));
      p = p.copyWith(alignMax: max);
      final bad = avgScore(st, {'malo', 'malo_vivo'}, p);
      if (bad > 56) break; // ya no se puede sostener la toma de 5 en 50
      if (avgScore(st, {'quieto_mitad'}, p) > kHalfStillMax) break;
      final good = avgScore(st, {'alumno_bien'}, p);
      if (good > bestGood) {
        bestGood = good;
        best = p;
      }
      if (good >= kGoodTarget) break;
    }
    final p = best ?? global;
    fitted[st] = p;
    stdout.writeln('${st.padRight(24)} floor ${p.alignNoiseFloor.toStringAsFixed(3)}'
        ' max ${p.alignMax.toStringAsFixed(3)}'
        '  alumno ${avgScore(st, {'alumno_bien'}, p).toStringAsFixed(1)}'
        '  malo ${avgScore(st, {'malo', 'malo_vivo'}, p).toStringAsFixed(1)}'
        '  quietoMitad ${avgScore(st, {'quieto_mitad'}, p).toStringAsFixed(1)}');
  }
  final rows = score(cases, (id) => fitted[id] ?? global);
  printSummary(rows, detail: false);
  stdout.writeln('\n// step_params.dart');
  for (final e in fitted.entries) {
    stdout.writeln("  '${e.key}': (floor: ${e.value.alignNoiseFloor.toStringAsFixed(3)}, "
        "max: ${e.value.alignMax.toStringAsFixed(3)}),");
  }
}


/// --groups: de qué partes del cuerpo sale el error (media de componentErrors
/// por grupo) en el alumno que lo hace bien frente a la toma de 5. Una parte
/// que pesa mucho en el alumno y poco en la toma mala solo mete ruido.
void printGroups(List<Case> cases, DtwParams p) {
  const groups = {
    'rodillas': [0, 1, 2, 3],
    'pies': [4, 5, 6, 7, 8, 11, 12, 13, 14],
    'rodX': [9, 10],
    'brazos': [15, 16, 18, 19, 20, 21],
    'hombros': [17],
    'cadera': [22, 23, 24, 25],
  };
  final rows = score(cases.where((c) => const {'alumno_bien', 'malo_vivo', 'quieto'}.contains(c.scenario.name)).toList(), (_) => p);
  final steps = rows.map((r) => r.step).toSet();
  for (final st in steps) {
    stdout.writeln(st);
    for (final sc in const ['alumno_bien', 'malo_vivo', 'quieto']) {
      final rs = rows.where((r) => r.step == st && r.scenario.name == sc).toList();
      final parts = groups.entries.map((g) {
        var v = 0.0;
        for (final r in rs) {
          for (final i in g.value) {
            v += r.result.componentErrors[i];
          }
        }
        return '${g.key} ${(v / rs.length).toStringAsFixed(2)}';
      }).join('  ');
      stdout.writeln('  ${sc.padRight(12)} rel ${(rs.map((r) => r.result.relativeCost).reduce((a, b) => a + b) / rs.length).toStringAsFixed(2)}  $parts');
    }
  }
}
