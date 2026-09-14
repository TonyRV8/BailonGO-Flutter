import 'dart:math' as math;

import 'dtw_params.dart';
import 'dtw_result.dart';
import 'feature_extractor.dart';

/// Port 1:1 de `DTWComparator.kt`. Compara la secuencia de features del usuario
/// contra la referencia con DTW (banda Sakoe-Chiba) y produce scores de
/// alineación y ritmo, con penalizaciones por cobertura y ejecución especular.
///
/// Todos los `const val` de ajuste del prototipo se conservan tal cual.
class DtwComparator {
  DtwComparator._();

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
    DtwParams params = DtwParams.defaults,
  }) {
    if (userFrames.isEmpty || refFrames.isEmpty) {
      return DtwResult.empty;
    }

    final uSmooth = _smooth(userFrames, params);
    final rSmooth = _smooth(refFrames, params);

    final n = uSmooth.length;
    final m = rSmooth.length;
    final w = math.max(
      math.max((math.max(n, m) * params.bandRatio).round(), 1),
      (n - m).abs(),
    );
    const inf = double.maxFinite / 2;

    final featureSize = math
        .min(uSmooth[0].length, rSmooth[0].length)
        .clamp(1, params.featureRanges.length)
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
            uSmooth[i - 1], rSmooth[j - 1], featureSize, w8, params);
        final compDist =
            _componentDistances(
            uSmooth[i - 1], rSmooth[j - 1], featureSize, w8, params);

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
    final segDevSignedSum = List<double>.filled(3, 0);
    final segDevCount = List<int>.filled(3, 0);

    // Por segmento: error abs ponderado y diferencia señada (user − ref,
    // normalizada por rango) por componente — base del feedback por tiempo.
    final segCompAbs =
        List.generate(3, (_) => List<double>.filled(featureSize, 0));
    final segCompSigned =
        List.generate(3, (_) => List<double>.filled(featureSize, 0));

    final idealSlope = m / n;
    final normDenom = math.max(n, m).toDouble();

    var directSum = 0.0;
    var mirrorSum = 0.0;
    var pathSteps = 0;

    var ci = n, cj = m;
    while (ci > 0 && cj > 0) {
      final cost = _normalizedEuclideanDist(
          uSmooth[ci - 1], rSmooth[cj - 1], featureSize, w8, params);
      final mirrorCost = _normalizedEuclideanDist(
          uSmooth[ci - 1], rMirrored[cj - 1], featureSize, w8, params);

      userFrameCostSum[ci] += cost;
      userFrameCount[ci]++;
      directSum += cost;
      mirrorSum += mirrorCost;
      pathSteps++;

      final seg = ((ci - 1) * 3 ~/ n).clamp(0, 2).toInt();
      final idealJ = ci * idealSlope;
      final signedDev = (cj - idealJ) / normDenom;
      segDevSum[seg] += signedDev.abs();
      segDevSignedSum[seg] += signedDev;
      segDevCount[seg]++;

      final u = uSmooth[ci - 1];
      final r = rSmooth[cj - 1];
      for (var c = 0; c < featureSize; c++) {
        final range = c < params.featureRanges.length ? params.featureRanges[c] : 1.0;
        final diff = (u[c] - r[c]) / range;
        segCompAbs[seg][c] += w8[c] * diff.abs();
        segCompSigned[seg][c] += diff;
      }

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
    final userEnergy = _motionEnergy(uSmooth, featureSize, w8, params);
    final refEnergy = _motionEnergy(rSmooth, featureSize, w8, params);
    final coverageRatio =
        refEnergy > 1e-4 ? math.max(userEnergy / refEnergy, 0.0) : 1.0;
    final coverageFactor = _coverageToFactor(coverageRatio, params);

    // ── Detección de ejecución especular ─────────────────────────────
    final directAvg = directSum / pathLen;
    final mirrorAvg = mirrorSum / pathLen;
    final mirrorFactor = _mirrorToFactor(directAvg, mirrorAvg, params);

    final alignFactor = coverageFactor * mirrorFactor;

    // ── Scores por segmento ──────────────────────────────────────────
    final segAlignment = List<int>.generate(3, (s) {
      if (segFrameCount[s] == 0) return 0;
      return _applyFactor(
          _costToAlignScore(segCostSum[s] / segFrameCount[s], params), alignFactor);
    });
    final segRhythm = List<int>.generate(3, (s) {
      if (segDevCount[s] == 0) return 0;
      return _applyFactor(
          _deviationToRhythmScore(segDevSum[s] / segDevCount[s], params),
          coverageFactor);
    });

    final segScore = List<int>.generate(
      3,
      (s) => (params.alignWeight * segAlignment[s] + params.rhythmWeight * segRhythm[s])
          .toInt()
          .clamp(0, 100)
          .toInt(),
    );
    final segTempo = List<double>.generate(
      3,
      (s) => segDevCount[s] > 0 ? segDevSignedSum[s] / segDevCount[s] : 0.0,
    );
    final segCompErrors = List<List<double>>.generate(
      3,
      (s) => segDevCount[s] > 0
          ? List<double>.generate(
              featureSize, (c) => segCompAbs[s][c] / segDevCount[s])
          : List<double>.filled(featureSize, 0),
    );
    final segSignedErrors = List<List<double>>.generate(
      3,
      (s) => segDevCount[s] > 0
          ? List<double>.generate(
              featureSize, (c) => segCompSigned[s][c] / segDevCount[s])
          : List<double>.filled(featureSize, 0),
    );

    // ── Scores globales ──────────────────────────────────────────────
    final totalFrames = math.max(segFrameCount.reduce((a, b) => a + b), 1);
    final alignmentAvg = segCostSum.reduce((a, b) => a + b) / totalFrames;
    final alignmentScore =
        _applyFactor(_costToAlignScore(alignmentAvg, params), alignFactor);

    final overallDev = segDevSum.reduce((a, b) => a + b) / pathLen;
    final rhythmScore =
        _applyFactor(_deviationToRhythmScore(overallDev, params), coverageFactor);

    final finalScore =
        (params.alignWeight * alignmentScore + params.rhythmWeight * rhythmScore)
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
      segmentScore: segScore,
      segmentTempo: segTempo,
      segmentComponentErrors: segCompErrors,
      segmentSignedErrors: segSignedErrors,
      componentErrors: componentErrors,
      worstComponentIndex: worstIdx,
    );
  }

  static int _costToAlignScore(double cost, DtwParams params) {
    if (cost <= params.alignNoiseFloor) return 100;
    if (cost >= params.alignMax) return 0;
    final linearF = 1 - (cost - params.alignNoiseFloor) / (params.alignMax - params.alignNoiseFloor);
    final curved = math.pow(linearF, params.alignCurvePower).toDouble();
    return (curved * 100).toInt().clamp(0, 100).toInt();
  }

  static int _deviationToRhythmScore(double dev, DtwParams params) {
    final double f;
    if (dev <= params.rhythmFullDev) {
      f = 1;
    } else if (dev >= params.rhythmZeroDev) {
      f = 0;
    } else {
      f = 1 - (dev - params.rhythmFullDev) / (params.rhythmZeroDev - params.rhythmFullDev);
    }
    return (f * 100).toInt().clamp(0, 100).toInt();
  }

  static double _coverageToFactor(double ratio, DtwParams params) {
    if (ratio >= params.coverageFullRatio) return 1;
    if (ratio <= params.coverageZeroRatio) return params.coverageMinFactor;
    final t =
        (ratio - params.coverageZeroRatio) / (params.coverageFullRatio - params.coverageZeroRatio);
    return params.coverageMinFactor + t * (1 - params.coverageMinFactor);
  }

  static int _applyFactor(int score, double factor) =>
      (score * factor).toInt().clamp(0, 100).toInt();

  static double _mirrorToFactor(
      double directAvg, double mirrorAvg, DtwParams params) {
    if (directAvg <= 1e-4 || mirrorAvg >= directAvg) return 1;
    final severity =
        ((directAvg - mirrorAvg) / directAvg).clamp(0.0, 1.0).toDouble();
    if (severity >= params.mirrorFullSeverity) return params.mirrorMinFactor;
    final t = severity / params.mirrorFullSeverity;
    return 1 - t * (1 - params.mirrorMinFactor);
  }

  static double _motionEnergy(List<List<double>> frames, int featureSize,
      List<double> weights, DtwParams params) {
    if (frames.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < frames.length; i++) {
      total += _normalizedEuclideanDist(
          frames[i], frames[i - 1], featureSize, weights, params);
    }
    return total / (frames.length - 1);
  }

  static List<List<double>> _smooth(
      List<List<double>> frames, DtwParams params) {
    final size = frames.length;
    if (size <= 2) return frames;
    final half = params.smoothWindow ~/ 2;
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

  static double _normalizedEuclideanDist(List<double> v1, List<double> v2,
      int size, List<double> weights, DtwParams params) {
    var sum = 0.0;
    var wsum = 0.0;
    for (var i = 0; i < size; i++) {
      final range = i < params.featureRanges.length ? params.featureRanges[i] : 1.0;
      final diff = (v1[i] - v2[i]) / range;
      sum += weights[i] * diff * diff;
      wsum += weights[i];
    }
    return wsum > 0 ? math.sqrt(sum / wsum) : 0.0;
  }

  static List<double> _componentDistances(List<double> v1, List<double> v2,
      int size, List<double> weights, DtwParams params) {
    final len = math.min(v1.length, size);
    return List<double>.generate(len, (it) {
      final range = it < params.featureRanges.length ? params.featureRanges[it] : 1.0;
      return weights[it] * (v1[it] - v2[it]).abs() / range;
    });
  }
}
