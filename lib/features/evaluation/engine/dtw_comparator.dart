import 'dart:math' as math;

import 'dtw_result.dart';
import 'feature_extractor.dart';

/// Port 1:1 de `DTWComparator.kt`. Compara la secuencia de features del usuario
/// contra la referencia con DTW (banda Sakoe-Chiba) y produce scores de
/// alineación y ritmo, con penalizaciones por cobertura y ejecución especular.
///
/// Todos los `const val` de ajuste del prototipo se conservan tal cual.
class DtwComparator {
  DtwComparator._();

  /// Zona muerta: costo promedio ≤ esto → alineación 100%.
  static const double _alignNoiseFloor = 0.09;

  /// Costo promedio ≥ esto → alineación 0%.
  static const double _alignMax = 0.19;

  /// Exponente de la curva costo→score (>1 castiga diferencias medianas).
  static const double _alignCurvePower = 2.0;

  /// Banda Sakoe-Chiba: máximo desfase como fracción de max(n, m).
  static const double _bandRatio = 0.12;

  /// Ventana centrada para suavizado pre-DTW.
  static const int _smoothWindow = 5;

  /// Ritmo: desviación del path respecto a la diagonal ideal.
  static const double _rhythmFullDev = 0.04;
  static const double _rhythmZeroDev = 0.25;

  /// Pesos alineación vs ritmo (RNF-06).
  static const double _alignWeight = 0.6;
  static const double _rhythmWeight = 0.4;

  /// Cobertura de movimiento (detecta ejecución incompleta).
  static const double _coverageFullRatio = 0.75;
  static const double _coverageZeroRatio = 0.25;
  static const double _coverageMinFactor = 0.4;

  /// Detección de ejecución especular.
  static const double _mirrorFullSeverity = 0.35;
  static const double _mirrorMinFactor = 0.15;

  static const List<double> _featureRanges = [
    120, // 0 knee angle
    120, // 1 knee angle
    2, // 2 leg inclination cosine
    2, // 3 leg inclination cosine
    5, // 4 feet distance ratio
    6, // 5 ankle height Y
    6, // 6 ankle height Y
    8, // 7 x ankle pos
    8, // 8 x ankle pos
    6, // 9 x knee pos
    6, // 10 x knee pos
    2, // 11 foot dir X
    2, // 12 foot dir X
    1, // 13 foot pitch
    1, // 14 foot pitch
    225, // 15 arm angle L
    225, // 16 arm angle R
    3, // 17 shoulder tilt
    9, // 18 wrist X rel L
    9, // 19 wrist X rel R
    9, // 20 wrist Y rel L
    9, // 21 wrist Y rel R
  ];

  /// Construye el vector de pesos efectivo (longitud [size]). Sin pesos: todos
  /// 1. Con pesos: usa los provistos; rellena con 1 si faltan componentes.
  static List<double> _effectiveWeights(List<double>? weights, int size) {
    return List<double>.generate(
      size,
      (i) => (weights != null && i < weights.length) ? weights[i] : 1.0,
    );
  }

  /// [weights]: peso por feature (longitud = nº de features del paso). Las
  /// features con peso 0 se ignoran en el costo, permitiendo ponderar landmarks
  /// distintos por paso (piernas vs brazos). Sin pesos: todas valen igual.
  static DtwResult compare(
    List<List<double>> userFrames,
    List<List<double>> refFrames, {
    List<double>? weights,
  }) {
    if (userFrames.isEmpty || refFrames.isEmpty) {
      return const DtwResult(
        score: 0,
        rhythmScore: 0,
        alignmentScore: 0,
        normalizedCost: 0,
        segmentRhythm: [0, 0, 0],
        segmentAlignment: [0, 0, 0],
        componentErrors: [],
        worstComponentIndex: 0,
      );
    }

    final uSmooth = _smooth(userFrames);
    final rSmooth = _smooth(refFrames);

    final n = uSmooth.length;
    final m = rSmooth.length;
    final w = math.max(
      math.max((math.max(n, m) * _bandRatio).round(), 1),
      (n - m).abs(),
    );
    const inf = double.maxFinite / 2;

    final featureSize = math
        .min(uSmooth[0].length, rSmooth[0].length)
        .clamp(1, _featureRanges.length)
        .toInt();
    final w8 = _effectiveWeights(weights, featureSize);

    final dtw = List.generate(n + 1, (_) => List<double>.filled(m + 1, inf));
    dtw[0][0] = 0;

    final parent = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    final compAccum = List.generate(
      n + 1,
      (_) => List.generate(m + 1, (_) => List<double>.filled(featureSize, 0)),
    );

    for (var i = 1; i <= n; i++) {
      final jLow = math.max(1, i - w);
      final jHigh = math.min(m, i + w);
      for (var j = jLow; j <= jHigh; j++) {
        final cost = _normalizedEuclideanDist(
            uSmooth[i - 1], rSmooth[j - 1], featureSize, w8);
        final compDist =
            _componentDistances(uSmooth[i - 1], rSmooth[j - 1], featureSize, w8);

        final c0 = dtw[i - 1][j - 1];
        final c1 = dtw[i - 1][j];
        final c2 = dtw[i][j - 1];
        final minCost = math.min(c0, math.min(c1, c2));

        final int pi, pj;
        if (minCost == c0) {
          pi = i - 1;
          pj = j - 1;
          parent[i][j] = 0;
        } else if (minCost == c1) {
          pi = i - 1;
          pj = j;
          parent[i][j] = 1;
        } else {
          pi = i;
          pj = j - 1;
          parent[i][j] = 2;
        }

        dtw[i][j] = minCost + cost;
        for (var c = 0; c < featureSize; c++) {
          compAccum[i][j][c] = compAccum[pi][pj][c] + compDist[c];
        }
      }
    }

    // ── Backtrack: costos por user-frame + desviación de path ───────
    final rMirrored =
        rSmooth.map((f) => FeatureExtractor.mirrorFeatures(f)).toList();

    final userFrameCostSum = List<double>.filled(n + 1, 0);
    final userFrameCount = List<int>.filled(n + 1, 0);

    final segDevSum = List<double>.filled(3, 0);
    final segDevCount = List<int>.filled(3, 0);

    final idealSlope = m / n;
    final normDenom = math.max(n, m).toDouble();

    var directSum = 0.0;
    var mirrorSum = 0.0;
    var pathSteps = 0;

    var ci = n, cj = m;
    while (ci > 0 && cj > 0) {
      final cost = _normalizedEuclideanDist(
          uSmooth[ci - 1], rSmooth[cj - 1], featureSize, w8);
      final mirrorCost = _normalizedEuclideanDist(
          uSmooth[ci - 1], rMirrored[cj - 1], featureSize, w8);

      userFrameCostSum[ci] += cost;
      userFrameCount[ci]++;
      directSum += cost;
      mirrorSum += mirrorCost;
      pathSteps++;

      final seg = ((ci - 1) * 3 ~/ n).clamp(0, 2).toInt();
      final idealJ = ci * idealSlope;
      segDevSum[seg] += (cj - idealJ).abs() / normDenom;
      segDevCount[seg]++;

      switch (parent[ci][cj]) {
        case 0:
          ci--;
          cj--;
          break;
        case 1:
          ci--;
          break;
        case 2:
          cj--;
          break;
        default:
          ci = 0;
          cj = 0;
      }
    }

    final pathLen = math.max(pathSteps, 1);
    final totalCost = dtw[n][m];

    // Costo promedio por user-frame, agrupado por segmento balanceado.
    final segCostSum = List<double>.filled(3, 0);
    final segFrameCount = List<int>.filled(3, 0);
    for (var i = 1; i <= n; i++) {
      if (userFrameCount[i] > 0) {
        final frameAvg = userFrameCostSum[i] / userFrameCount[i];
        final seg = ((i - 1) * 3 ~/ n).clamp(0, 2).toInt();
        segCostSum[seg] += frameAvg;
        segFrameCount[seg]++;
      }
    }

    // ── Cobertura de movimiento ──────────────────────────────────────
    final userEnergy = _motionEnergy(uSmooth, featureSize, w8);
    final refEnergy = _motionEnergy(rSmooth, featureSize, w8);
    final coverageRatio =
        refEnergy > 1e-4 ? math.max(userEnergy / refEnergy, 0.0) : 1.0;
    final coverageFactor = _coverageToFactor(coverageRatio);

    // ── Detección de ejecución especular ─────────────────────────────
    final directAvg = directSum / pathLen;
    final mirrorAvg = mirrorSum / pathLen;
    final mirrorFactor = _mirrorToFactor(directAvg, mirrorAvg);

    final alignFactor = coverageFactor * mirrorFactor;

    // ── Scores por segmento ──────────────────────────────────────────
    final segAlignment = List<int>.generate(3, (s) {
      if (segFrameCount[s] == 0) return 0;
      return _applyFactor(
          _costToAlignScore(segCostSum[s] / segFrameCount[s]), alignFactor);
    });
    final segRhythm = List<int>.generate(3, (s) {
      if (segDevCount[s] == 0) return 0;
      return _applyFactor(
          _deviationToRhythmScore(segDevSum[s] / segDevCount[s]),
          coverageFactor);
    });

    // ── Scores globales ──────────────────────────────────────────────
    final totalFrames = math.max(segFrameCount.reduce((a, b) => a + b), 1);
    final alignmentAvg = segCostSum.reduce((a, b) => a + b) / totalFrames;
    final alignmentScore =
        _applyFactor(_costToAlignScore(alignmentAvg), alignFactor);

    final overallDev = segDevSum.reduce((a, b) => a + b) / pathLen;
    final rhythmScore =
        _applyFactor(_deviationToRhythmScore(overallDev), coverageFactor);

    final finalScore =
        (_alignWeight * alignmentScore + _rhythmWeight * rhythmScore)
            .toInt()
            .clamp(0, 100)
            .toInt();

    final avgLen = (n + m) / 2;
    final normalizedCost = avgLen > 0 ? totalCost / avgLen : 0.0;

    final componentErrors = List<double>.generate(
        featureSize, (it) => compAccum[n][m][it] / pathLen);
    var worstIdx = 0;
    for (var i = 1; i < componentErrors.length; i++) {
      if (componentErrors[i] > componentErrors[worstIdx]) worstIdx = i;
    }

    return DtwResult(
      score: finalScore,
      rhythmScore: rhythmScore,
      alignmentScore: alignmentScore,
      normalizedCost: normalizedCost,
      segmentRhythm: segRhythm,
      segmentAlignment: segAlignment,
      componentErrors: componentErrors,
      worstComponentIndex: worstIdx,
    );
  }

  static int _costToAlignScore(double cost) {
    if (cost <= _alignNoiseFloor) return 100;
    if (cost >= _alignMax) return 0;
    final linearF = 1 - (cost - _alignNoiseFloor) / (_alignMax - _alignNoiseFloor);
    final curved = math.pow(linearF, _alignCurvePower).toDouble();
    return (curved * 100).toInt().clamp(0, 100).toInt();
  }

  static int _deviationToRhythmScore(double dev) {
    final double f;
    if (dev <= _rhythmFullDev) {
      f = 1;
    } else if (dev >= _rhythmZeroDev) {
      f = 0;
    } else {
      f = 1 - (dev - _rhythmFullDev) / (_rhythmZeroDev - _rhythmFullDev);
    }
    return (f * 100).toInt().clamp(0, 100).toInt();
  }

  static double _coverageToFactor(double ratio) {
    if (ratio >= _coverageFullRatio) return 1;
    if (ratio <= _coverageZeroRatio) return _coverageMinFactor;
    final t =
        (ratio - _coverageZeroRatio) / (_coverageFullRatio - _coverageZeroRatio);
    return _coverageMinFactor + t * (1 - _coverageMinFactor);
  }

  static int _applyFactor(int score, double factor) =>
      (score * factor).toInt().clamp(0, 100).toInt();

  static double _mirrorToFactor(double directAvg, double mirrorAvg) {
    if (directAvg <= 1e-4 || mirrorAvg >= directAvg) return 1;
    final severity =
        ((directAvg - mirrorAvg) / directAvg).clamp(0.0, 1.0).toDouble();
    if (severity >= _mirrorFullSeverity) return _mirrorMinFactor;
    final t = severity / _mirrorFullSeverity;
    return 1 - t * (1 - _mirrorMinFactor);
  }

  static double _motionEnergy(
      List<List<double>> frames, int featureSize, List<double> weights) {
    if (frames.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < frames.length; i++) {
      total += _normalizedEuclideanDist(
          frames[i], frames[i - 1], featureSize, weights);
    }
    return total / (frames.length - 1);
  }

  static List<List<double>> _smooth(List<List<double>> frames) {
    final size = frames.length;
    if (size <= 2) return frames;
    const half = _smoothWindow ~/ 2;
    final featSize = frames[0].length;
    return List.generate(size, (i) {
      final start = math.max(i - half, 0);
      final end = math.min(i + half + 1, size);
      final count = end - start;
      final avg = List<double>.filled(featSize, 0);
      for (var k = start; k < end; k++) {
        final f = frames[k];
        for (var c = 0; c < featSize; c++) {
          avg[c] += f[c];
        }
      }
      for (var c = 0; c < featSize; c++) {
        avg[c] /= count;
      }
      return avg;
    });
  }

  static double _normalizedEuclideanDist(
      List<double> v1, List<double> v2, int size, List<double> weights) {
    var sum = 0.0;
    var wsum = 0.0;
    for (var i = 0; i < size; i++) {
      final range = i < _featureRanges.length ? _featureRanges[i] : 1.0;
      final diff = (v1[i] - v2[i]) / range;
      sum += weights[i] * diff * diff;
      wsum += weights[i];
    }
    return wsum > 0 ? math.sqrt(sum / wsum) : 0.0;
  }

  static List<double> _componentDistances(
      List<double> v1, List<double> v2, int size, List<double> weights) {
    final len = math.min(v1.length, size);
    return List<double>.generate(len, (it) {
      final range = it < _featureRanges.length ? _featureRanges[it] : 1.0;
      return weights[it] * (v1[it] - v2[it]).abs() / range;
    });
  }
}
