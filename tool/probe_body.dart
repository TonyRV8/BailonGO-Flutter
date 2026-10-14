/// Sonda: ¿cuánto afecta a la nota el TIPO DE CUERPO y cuánto el ÁNGULO DE
/// CÁMARA? Se parte de la referencia de cada paso y se la evalúa contra sí
/// misma tras aplicarle dos deformaciones distintas:
///
///   cuerpo   escala lineal de la componente vertical respecto al centro de
///            la cadera. Equivale a la misma persona con las piernas más
///            largas o más cortas, o a una toma vista desde la misma altura
///            con otra proporción corporal.
///   cámara   compresión NO lineal de la vertical, que es lo que hace de
///            verdad cambiar la altura del teléfono: lo que está cerca del
///            suelo se aplasta más que lo que está a la altura del objetivo.
///
/// Si la nota aguanta la primera y se hunde con la segunda, el problema no es
/// la complexión del usuario sino la perspectiva, y normalizar por el propio
/// cuerpo no lo arregla.
///
/// Uso: dart run tool/probe_body.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/engine/dtw_comparator.dart';
import 'package:bailongo/features/evaluation/engine/feature_extractor.dart';
import 'package:bailongo/features/evaluation/engine/step_params.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';

List<PoseLandmark> toLandmarks(List<double> flat) => [
      for (var i = 0; i + 3 < flat.length; i += 4)
        PoseLandmark(
            type: i ~/ 4,
            x: flat[i],
            y: flat[i + 1],
            z: flat[i + 2],
            confidence: flat[i + 3]),
    ];

/// Escala la vertical por [k] respecto al centro de la cadera: otra
/// complexión, misma perspectiva.
List<double> body(List<double> f, double k) {
  final out = List<double>.from(f);
  final hy = (f[23 * 4 + 1] + f[24 * 4 + 1]) / 2;
  for (var i = 0; i < 33; i++) {
    out[i * 4 + 1] = hy + (f[i * 4 + 1] - hy) * k;
  }
  return out;
}

/// Compresión no lineal de la vertical: lo que está por debajo del centro de
/// la cadera se aplasta progresivamente, que es el efecto de subir la cámara.
/// [k] = 0 no cambia nada; 0.3 equivale a una cámara bastante más alta.
List<double> camera(List<double> f, double k) {
  final out = List<double>.from(f);
  final hy = (f[23 * 4 + 1] + f[24 * 4 + 1]) / 2;
  for (var i = 0; i < 33; i++) {
    final dy = f[i * 4 + 1] - hy;
    out[i * 4 + 1] = hy + dy * (1 - k * dy.abs() * 2);
  }
  return out;
}

List<List<double>> featuresOf(List<List<double>> frames, double aspect,
    List<double> Function(List<double>) warp) {
  final out = <List<double>>[];
  for (final f in frames) {
    final v = FeatureExtractor.extractFeatures(toLandmarks(warp(f)),
        aspectRatio: aspect);
    if (v != null) out.add(v);
  }
  return out;
}

void main() {
  final raw = jsonDecode(File('tool/landmarks.json').readAsStringSync())
      as Map<String, dynamic>;
  const steps = kRealStepIds;
  stdout.writeln('nota de la referencia evaluada contra sí misma tras '
      'deformarla\n');
  stdout.writeln('${'paso'.padRight(24)}'
      '${'cuerpo x0.8'.padLeft(12)}${'x1.25'.padLeft(8)}'
      '${'cámara 0.15'.padLeft(13)}${'0.30'.padLeft(8)}');
  final acc = <String, List<double>>{
    'b08': [], 'b125': [], 'c015': [], 'c030': []
  };
  for (final id in steps) {
    final e = raw[id] as Map<String, dynamic>;
    final frames = [
      for (final f in e['frames'] as List)
        (f as List).map((x) => (x as num).toDouble()).toList(),
    ];
    final aspect = ((e['height'] as num?) ?? 1280) / ((e['width'] as num?) ?? 720);
    final ref = featuresOf(frames, aspect, (f) => f);
    final p = paramsFor(id);
    final w = weightsForStep(id);
    int score(List<double> Function(List<double>) warp) =>
        DtwComparator.compare(featuresOf(frames, aspect, warp), ref,
                weights: w, params: p)
            .score;
    final b08 = score((f) => body(f, 0.8));
    final b125 = score((f) => body(f, 1.25));
    final c015 = score((f) => camera(f, 0.15));
    final c030 = score((f) => camera(f, 0.30));
    acc['b08']!.add(b08.toDouble());
    acc['b125']!.add(b125.toDouble());
    acc['c015']!.add(c015.toDouble());
    acc['c030']!.add(c030.toDouble());
    stdout.writeln('${id.padRight(24)}${b08.toString().padLeft(12)}'
        '${b125.toString().padLeft(8)}${c015.toString().padLeft(13)}'
        '${c030.toString().padLeft(8)}');
  }
  double m(String k) =>
      acc[k]!.reduce((a, b) => a + b) / acc[k]!.length;
  stdout.writeln('${'media'.padRight(24)}${m('b08').round().toString().padLeft(12)}'
      '${m('b125').round().toString().padLeft(8)}'
      '${m('c015').round().toString().padLeft(13)}'
      '${m('c030').round().toString().padLeft(8)}');
  stdout.writeln('\n(sin deformar, la referencia contra sí misma da 100)');
}
