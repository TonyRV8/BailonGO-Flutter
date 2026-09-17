import 'dart:math' as math;

import 'dtw_params.dart';
import 'dtw_result.dart';
import 'feature_extractor.dart';

/// Compara la secuencia de features del usuario contra la referencia y produce
/// la precisión total (RNF-06: 0.6·alineación + 0.4·ritmo) con su desglose por
/// tiempo (inicio / medio / final).
///
/// Origen: port de `DTWComparator.kt`. Revisión 2 (2026-09-17), rediseñada con
/// el banco de escenarios `tool/bench.dart` porque la versión portada fallaba
/// en uso real de dos formas opuestas:
///   * quedarse quieto a media ejecución daba 99 % (cucaracha), y
///   * bailar bien delante del teléfono no pasaba de 75 %.
///
/// Qué cambió y por qué:
///
/// 1. POSTURA vs MOVIMIENTO. Cada secuencia se CENTRA restando la mediana de
///    cada feature. Así el DTW compara el movimiento y no la complexión, la
///    altura de la cámara o el ancho de cadera de cada persona, que antes se
///    sumaban como error en cada fotograma. La postura media se sigue midiendo,
///    aparte y con poco peso ([DtwParams.offsetWeight]).
///
/// 2. COSTE RELATIVO. El coste de alineación se divide por el coste de "no
///    moverse" contra ESA referencia (la postura media frente a cada fotograma
///    del modelo). 0 = idéntico, 1 = tan lejos como estar quieto. Es una escala
///    común a los nueve pasos: antes el mismo nivel de calidad costaba 25 veces
///    más en kick_flick que en el básico y cada paso necesitaba su curva, lo
///    que dejó la de cucaracha tan laxa que estar quieto sacaba 99 %.
///
/// 3. COBERTURA POR VENTANAS. La amplitud del movimiento se compara en
///    ventanas de ~1 s, no en todo el intento: pararse a la mitad deja la mitad
///    de las ventanas vacías. La amplitud (desviación dentro de la ventana) es
///    además inmune al temblor del detector, que sí inflaba la antigua
///    "energía" fotograma a fotograma.
///
/// 4. RITMO POR ACENTOS. El ritmo antiguo medía cuánto se torcía el camino DTW,
///    y un camino recto sale también cuando no hay movimiento que alinear (el
///    que estaba quieto sacaba 100 de ritmo). Ahora se correlaciona el perfil
///    de VELOCIDAD del usuario con el del modelo en ventanas de ~2 s, dejando
///    un pequeño margen de reacción: los acentos del paso tienen que caer
///    donde caen en el modelo. La desviación del camino se conserva para los
///    consejos de "vas adelantado / atrasado".
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
  ///
  /// Ambas secuencias deben estar en la misma rejilla temporal (un vector cada
  /// 33 ms): en vivo, pasar antes por `FrameResampler.toGrid`.
  static DtwResult compare(
    List<List<double>> userFrames,
    List<List<double>> refFrames, {
    List<double>? weights,
    DtwParams params = DtwParams.defaults,
  }) {
    if (userFrames.isEmpty || refFrames.isEmpty) {
      return DtwResult.empty;
    }

    final featureSize = math
        .min(userFrames[0].length, refFrames[0].length)
        .clamp(1, params.featureRanges.length)
        .toInt();

    // Todo se trabaja en unidades de rango: (valor / rango de la feature).
    final uRaw = _smooth(_scaled(userFrames, featureSize, params), params);
    final rRaw = _smooth(_scaled(refFrames, featureSize, params), params);
    var uMed = _median(uRaw, featureSize);
    var rMed = _median(rRaw, featureSize);
    var u = params.centerFeatures ? _centered(uRaw, uMed) : uRaw;
    var r = params.centerFeatures ? _centered(rRaw, rMed) : rRaw;

    // Peso efectivo = peso del paso x fiabilidad de la feature EN ESTE PASO.
    // Una feature que en el modelo se mueve menos que el temblor del detector
    // en vivo no puede distinguir un buen intento de uno malo: solo mete ruido
    // (p.ej. la inclinación de cadera o el pitch del pie en el básico).
    var noise = _noiseFor(featureSize, params);
    final refAmp = _featureAmplitudes(r, featureSize, params.coverageWindow);
    final base = _effectiveWeights(weights, featureSize);
    final w8 = List<double>.generate(featureSize, (c) {
      final a2 = refAmp[c] * refAmp[c];
      final n2 = params.snrK * noise[c] * noise[c];
      return a2 + n2 > 0 ? base[c] * a2 / (a2 + n2) : 0.0;
    });
    final wsum = w8.fold<double>(0, (a, b) => a + b);
    if (wsum <= 0) return DtwResult.empty;

    // Escala por paso: cada feature se mide en "cuánto se mueve en ESTE
    // paso" y no en su rango global. Sin esto, en pasos donde las piernas
    // apenas se ven moverse en 2D (guapeo, suzy q) los brazos, que se mueven
    // 5-10 veces más, dominaban el coste aunque pesaran 0.25: un alumno con
    // otro braceo sacaba alineación 0 con el ritmo perfecto. Así los pesos
    // del paso (piernas > hombros > brazos) son los que deciden.
    if (params.amplitudeNormalize) {
      final spread = _featureSpread(r, featureSize);
      final scale = List<double>.generate(
          featureSize,
          (c) => math.max(spread[c],
              math.max(params.amplitudeNoiseMul * noise[c], 1e-6)));
      u = _divided(u, scale);
      r = _divided(r, scale);
      uMed = [for (var c = 0; c < featureSize; c++) uMed[c] / scale[c]];
      rMed = [for (var c = 0; c < featureSize; c++) rMed[c] / scale[c]];
      noise = [for (var c = 0; c < featureSize; c++) noise[c] / scale[c]];
    }

    final n = u.length;
    final m = r.length;
    final band = math.max(
      math.max((math.max(n, m) * params.bandRatio).round(), 1),
      (n - m).abs(),
    );

    // ── DTW con banda Sakoe-Chiba ────────────────────────────────────
    // Solo se guarda la franja de la banda (O(n·banda) en memoria): la matriz
    // completa de acumulados por componente de la versión anterior reservaba
    // n·m·26 dobles (~75 MB para 20 s), inasumible en un teléfono.
    const inf = double.maxFinite / 2;
    final width = 2 * band + 1;
    final acc = List<double>.filled((n + 1) * width, inf);
    final parent = List<int>.filled((n + 1) * width, -1);
    int col(int i, int j) => j - i + band; // j ∈ [i-band, i+band]

    double at(int i, int j) {
      if (i == 0 && j == 0) return 0;
      if (i <= 0 || j <= 0) return inf;
      final c = col(i, j);
      if (c < 0 || c >= width) return inf;
      return acc[i * width + c];
    }

    for (var i = 1; i <= n; i++) {
      final jLow = math.max(1, i - band);
      final jHigh = math.min(m, i + band);
      for (var j = jLow; j <= jHigh; j++) {
        final cost = _dist(u[i - 1], r[j - 1], featureSize, w8, wsum, params);
        final c0 = at(i - 1, j - 1);
        final c1 = at(i - 1, j);
        final c2 = at(i, j - 1);
        final int p;
        final double best;
        if (c0 <= c1 && c0 <= c2) {
          best = c0;
          p = 0;
        } else if (c1 <= c2) {
          best = c1;
          p = 1;
        } else {
          best = c2;
          p = 2;
        }
        acc[i * width + col(i, j)] = best + cost;
        parent[i * width + col(i, j)] = p;
      }
    }
    final totalCost = at(n, m);

    // ── Backtrack ────────────────────────────────────────────────────
    final rMirrored = r.map(FeatureExtractor.mirrorFeatures).toList();

    final userFrameCostSum = List<double>.filled(n + 1, 0);
    final userFrameCount = List<int>.filled(n + 1, 0);

    final segDevSum = List<double>.filled(3, 0);
    final segDevSignedSum = List<double>.filled(3, 0);
    final segDevCount = List<int>.filled(3, 0);
    final segCompAbs =
        List.generate(3, (_) => List<double>.filled(featureSize, 0));
    final segCompSigned =
        List.generate(3, (_) => List<double>.filled(featureSize, 0));
    final componentSum = List<double>.filled(featureSize, 0);

    final idealSlope = m / n;
    final normDenom = math.max(n, m).toDouble();

    var directSum = 0.0;
    var mirrorSum = 0.0;
    var pathSteps = 0;

    var ci = n, cj = m;
    while (ci > 0 && cj > 0) {
      final ui = u[ci - 1];
      final rj = r[cj - 1];
      final cost = _dist(ui, rj, featureSize, w8, wsum, params);
      userFrameCostSum[ci] += cost;
      userFrameCount[ci]++;
      directSum += cost;
      mirrorSum +=
          _dist(ui, rMirrored[cj - 1], featureSize, w8, wsum, params);
      pathSteps++;

      final seg = _segmentOf(ci - 1, n);
      final signedDev = (cj - ci * idealSlope) / normDenom;
      segDevSum[seg] += signedDev.abs();
      segDevSignedSum[seg] += signedDev;
      segDevCount[seg]++;

      for (var c = 0; c < featureSize; c++) {
        final diff = ui[c] - rj[c];
        final e = w8[c] * diff.abs();
        segCompAbs[seg][c] += e;
        segCompSigned[seg][c] += diff;
        componentSum[c] += e;
      }

      final p = parent[ci * width + col(ci, cj)];
      if (p == 0) {
        ci--;
        cj--;
      } else if (p == 1) {
        ci--;
      } else if (p == 2) {
        cj--;
      } else {
        break;
      }
    }
    final pathLen = math.max(pathSteps, 1);

    // Costo promedio por fotograma de usuario, agrupado por segmento.
    final segCostSum = List<double>.filled(3, 0);
    final segFrameCount = List<int>.filled(3, 0);
    for (var i = 1; i <= n; i++) {
      if (userFrameCount[i] > 0) {
        final seg = _segmentOf(i - 1, n);
        segCostSum[seg] += userFrameCostSum[i] / userFrameCount[i];
        segFrameCount[seg]++;
      }
    }

    // ── Coste relativo: frente a "quedarse quieto" ───────────────────
    // Quieto en la postura media = vector centrado nulo. Se calcula por
    // segmento porque hay tramos del paso que se mueven más que otros.
    final zero = List<double>.filled(featureSize, 0);
    final segStill = List<double>.filled(3, 0);
    final segStillCount = List<int>.filled(3, 0);
    for (var j = 0; j < m; j++) {
      final s = _segmentOf(j, m);
      segStill[s] += _dist(zero, r[j], featureSize, w8, wsum, params);
      segStillCount[s]++;
    }
    final stillAll = segStill.reduce((a, b) => a + b) / math.max(m, 1);
    double relative(double cost, double still) =>
        cost / math.max(still, math.max(stillAll * 0.5, params.minMotion));

    // Postura media (lo que el centrado quitó), con poco peso y sin las
    // features que dependen de la complexión.
    final offset = params.centerFeatures && params.offsetWeight > 0
        ? relative(_offsetDist(uMed, rMed, featureSize, w8, params), stillAll)
        : 0.0;

    // ── Cobertura de movimiento por ventanas ─────────────────────────
    final coverage = _coverage(u, r, featureSize, w8, wsum, noise, params);
    final coverageFactor = _coverageToFactor(coverage.all, params);

    // ── Espejo ───────────────────────────────────────────────────────
    final directAvg = directSum / pathLen;
    final mirrorAvg = mirrorSum / pathLen;
    final mirrorFactor = _mirrorToFactor(directAvg, mirrorAvg, params);

    // ── Ritmo por correlación de acentos ─────────────────────────────
    final rhythm = _rhythm(u, r, featureSize, w8, wsum, params);

    int alignScore(double cost, double still, double cov) {
      final rel = relative(cost, still);
      final withOffset =
          math.sqrt(rel * rel + params.offsetWeight * offset * offset);
      final base = _costToAlignScore(withOffset, params);
      return _applyFactor(
          base, mirrorFactor * _coverageToFactor(cov, params));
    }

    int rhythmScore(double corrScore, double cov) =>
        _applyFactor((corrScore * 100).round(),
            mirrorFactor * _coverageToFactor(cov, params));

    // ── Scores por segmento ──────────────────────────────────────────
    final segAlignment = List<int>.generate(3, (s) {
      if (segFrameCount[s] == 0 || segStillCount[s] == 0) return 0;
      return alignScore(segCostSum[s] / segFrameCount[s],
          segStill[s] / segStillCount[s], coverage.segments[s]);
    });
    final segRhythm = List<int>.generate(
        3, (s) => rhythmScore(rhythm.segments[s], coverage.segments[s]));
    final segScore = List<int>.generate(
      3,
      (s) => (params.alignWeight * segAlignment[s] +
              params.rhythmWeight * segRhythm[s])
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
    // Global = media de los tramos, no un cálculo aparte: si un tercio del
    // intento está vacío, la nota tiene que notarlo en esa proporción.
    final alignmentScore = params.globalFromSegments
        ? (segAlignment.reduce((a, b) => a + b) / 3).round()
        : alignScore(alignmentAvg, stillAll, coverage.all);
    final rhythmScoreAll = params.globalFromSegments
        ? (segRhythm.reduce((a, b) => a + b) / 3).round()
        : rhythmScore(rhythm.all, coverage.all);

    final finalScore = (params.alignWeight * alignmentScore +
            params.rhythmWeight * rhythmScoreAll)
        .toInt()
        .clamp(0, 100)
        .toInt();

    final avgLen = (n + m) / 2;
    final normalizedCost = avgLen > 0 ? totalCost / avgLen : 0.0;

    final componentErrors = List<double>.generate(
        featureSize, (c) => componentSum[c] / pathLen);
    var worstIdx = 0;
    for (var i = 1; i < componentErrors.length; i++) {
      if (componentErrors[i] > componentErrors[worstIdx]) worstIdx = i;
    }

    return DtwResult(
      score: finalScore,
      rhythmScore: rhythmScoreAll,
      alignmentScore: alignmentScore,
      normalizedCost: normalizedCost,
      relativeCost: relative(alignmentAvg, stillAll),
      coverage: coverage.all,
      coverageFactor: coverageFactor,
      mirrorFactor: mirrorFactor,
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

  static int _segmentOf(int index, int length) =>
      (index * 3 ~/ math.max(length, 1)).clamp(0, 2).toInt();

  static int _costToAlignScore(double rel, DtwParams params) {
    if (rel <= params.alignNoiseFloor) return 100;
    if (rel >= params.alignMax) return 0;
    final linearF = 1 -
        (rel - params.alignNoiseFloor) /
            (params.alignMax - params.alignNoiseFloor);
    final curved = math.pow(linearF, params.alignCurvePower).toDouble();
    return (curved * 100).round().clamp(0, 100).toInt();
  }

  static double _coverageToFactor(double ratio, DtwParams params) {
    if (ratio >= params.coverageFullRatio) return 1;
    if (ratio <= params.coverageZeroRatio) return params.coverageMinFactor;
    final t = (ratio - params.coverageZeroRatio) /
        (params.coverageFullRatio - params.coverageZeroRatio);
    return params.coverageMinFactor + t * (1 - params.coverageMinFactor);
  }

  static int _applyFactor(int score, double factor) =>
      (score * factor).round().clamp(0, 100).toInt();

  static double _mirrorToFactor(
      double directAvg, double mirrorAvg, DtwParams params) {
    if (directAvg <= 1e-4 || mirrorAvg >= directAvg) return 1;
    final severity =
        ((directAvg - mirrorAvg) / directAvg).clamp(0.0, 1.0).toDouble();
    if (severity >= params.mirrorFullSeverity) return params.mirrorMinFactor;
    final t = severity / params.mirrorFullSeverity;
    return 1 - t * (1 - params.mirrorMinFactor);
  }

  /// Amplitud del usuario frente a la del modelo, por ventanas. La ventana del
  /// usuario es la misma franja temporal (ambas secuencias comparten rejilla).
  /// Las ventanas en que el modelo casi no se mueve no cuentan: ahí no hay
  /// nada que cubrir.
  static ({double all, List<double> segments}) _coverage(
    List<List<double>> u,
    List<List<double>> r,
    int size,
    List<double> w8,
    double wsum,
    List<double> noise,
    DtwParams params,
  ) {
    final n = u.length, m = r.length;
    final win = math.max(4, math.min(params.coverageWindow, m));
    final hop = math.max(1, win ~/ 2);
    final amps = <({double ref, double ratio, int seg})>[];
    for (var start = 0; start + win <= m; start += hop) {
      final ampR = _amplitude(r, start, start + win, size, w8, wsum, null);
      final uStart = (start * n / m).floor();
      final uEnd = math.min(n, math.max(uStart + 2, ((start + win) * n / m).ceil()));
      final ampU = _amplitude(u, uStart, uEnd, size, w8, wsum, noise);
      final ratio = ampR > 1e-9 ? math.min(ampU / ampR, 1.0) : 1.0;
      amps.add((ref: ampR, ratio: ratio, seg: _segmentOf(start + win ~/ 2, m)));
    }
    if (amps.isEmpty) return (all: 1.0, segments: [1.0, 1.0, 1.0]);

    final sorted = amps.map((a) => a.ref).toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    final minRef =
        math.max(median * params.coverageIgnoreBelow, params.minMotion * 0.25);

    double avg(Iterable<({double ref, double ratio, int seg})> xs) {
      var num = 0.0, den = 0.0;
      for (final a in xs) {
        if (a.ref < minRef) continue;
        num += a.ref * a.ratio;
        den += a.ref;
      }
      return den > 0 ? num / den : 1.0;
    }

    final all = avg(amps);
    final segments = List<double>.generate(3, (s) {
      final xs = amps.where((a) => a.seg == s);
      return xs.isEmpty ? all : avg(xs);
    });
    return (all: all, segments: segments);
  }

  /// Desviación ponderada (RMS) respecto a la media de la ventana. Con
  /// [noise], se descuenta la varianza del temblor: quedarse quieto delante de
  /// la cámara no cuenta como movimiento.
  static double _amplitude(List<List<double>> f, int start, int end, int size,
      List<double> w8, double wsum, List<double>? noise) {
    final len = end - start;
    if (len < 2) return 0;
    var total = 0.0;
    for (var c = 0; c < size; c++) {
      if (w8[c] == 0) continue;
      var mean = 0.0;
      for (var t = start; t < end; t++) {
        mean += f[t][c];
      }
      mean /= len;
      var v = 0.0;
      for (var t = start; t < end; t++) {
        final d = f[t][c] - mean;
        v += d * d;
      }
      v /= len;
      if (noise != null) v = math.max(0, v - noise[c] * noise[c]);
      total += w8[c] * v;
    }
    return math.sqrt(total / wsum);
  }

  /// Ritmo: correlación del perfil de velocidad (cuándo acelera y frena el
  /// cuerpo) entre usuario y modelo, por ventanas y con margen de reacción.
  /// Devuelve valores 0..1.
  static ({double all, List<double> segments}) _rhythm(
    List<List<double>> u,
    List<List<double>> r,
    int size,
    List<double> w8,
    double wsum,
    DtwParams params,
  ) {
    final su = _speed(u, size, w8, wsum, params);
    final sr = _speed(r, size, w8, wsum, params);
    final n = su.length, m = sr.length;
    if (n < 8 || m < 8) return (all: 1.0, segments: [1.0, 1.0, 1.0]);

    final win = math.max(8, math.min(params.rhythmWindow, m));
    final hop = math.max(1, win ~/ 2);
    final lagMax = params.rhythmMaxLag;
    final scores = <({double score, double weight, int seg})>[];
    for (var start = 0; start + win <= m; start += hop) {
      final refWin = sr.sublist(start, start + win);
      final refStd = _std(refWin);
      var best = -1.0;
      for (var lag = -lagMax; lag <= lagMax; lag++) {
        final us = (start * n / m).round() + lag;
        if (us < 0 || us + win > n) continue;
        final c = _pearson(su.sublist(us, us + win), refWin);
        if (c > best) best = c;
      }
      final t = ((best - params.rhythmCorrZero) /
              (params.rhythmCorrFull - params.rhythmCorrZero))
          .clamp(0.0, 1.0)
          .toDouble();
      scores.add((
        score: t,
        weight: refStd,
        seg: _segmentOf(start + win ~/ 2, m),
      ));
    }
    if (scores.isEmpty) return (all: 1.0, segments: [1.0, 1.0, 1.0]);

    // Ventanas en que el modelo lleva velocidad constante no dicen nada del
    // ritmo (la correlación ahí es ruido): pesan según cuánto varía el modelo.
    final sortedW = scores.map((s) => s.weight).toList()..sort();
    final medW = sortedW[sortedW.length ~/ 2];
    double avg(Iterable<({double score, double weight, int seg})> xs) {
      var num = 0.0, den = 0.0;
      for (final x in xs) {
        final wt = math.min(x.weight, medW * 2);
        if (wt < medW * 0.2) continue;
        num += wt * x.score;
        den += wt;
      }
      return den > 0 ? num / den : 1.0;
    }

    final all = avg(scores);
    final segments = List<double>.generate(3, (s) {
      final xs = scores.where((x) => x.seg == s);
      return xs.isEmpty ? all : avg(xs);
    });
    return (all: all, segments: segments);
  }

  /// Velocidad por fotograma (distancia ponderada entre fotogramas
  /// consecutivos), suavizada para que el temblor del detector no domine.
  static List<double> _speed(List<List<double>> f, int size, List<double> w8,
      double wsum, DtwParams params) {
    if (f.length < 2) return const [];
    final raw = List<double>.generate(f.length - 1, (t) {
      var s = 0.0;
      for (var c = 0; c < size; c++) {
        final d = f[t + 1][c] - f[t][c];
        s += w8[c] * d * d;
      }
      return math.sqrt(s / wsum);
    });
    final half = params.rhythmSmooth ~/ 2;
    return List<double>.generate(raw.length, (i) {
      final a = math.max(0, i - half);
      final b = math.min(raw.length, i + half + 1);
      var s = 0.0;
      for (var k = a; k < b; k++) {
        s += raw[k];
      }
      return s / (b - a);
    });
  }

  static double _std(List<double> x) {
    final mean = x.reduce((a, b) => a + b) / x.length;
    var v = 0.0;
    for (final e in x) {
      v += (e - mean) * (e - mean);
    }
    return math.sqrt(v / x.length);
  }

  static double _pearson(List<double> a, List<double> b) {
    final len = math.min(a.length, b.length);
    var ma = 0.0, mb = 0.0;
    for (var i = 0; i < len; i++) {
      ma += a[i];
      mb += b[i];
    }
    ma /= len;
    mb /= len;
    var sab = 0.0, saa = 0.0, sbb = 0.0;
    for (var i = 0; i < len; i++) {
      final da = a[i] - ma, db = b[i] - mb;
      sab += da * db;
      saa += da * da;
      sbb += db * db;
    }
    if (saa <= 1e-12 || sbb <= 1e-12) return 0;
    return sab / math.sqrt(saa * sbb);
  }

  /// Distancia entre posturas medias, sin las features que cambian con la
  /// complexión (separación de pies, altura del tobillo y de la cadera
  /// respecto al torso, ancho de cadera frente a hombros).
  static double _offsetDist(List<double> a, List<double> b, int size,
      List<double> w8, DtwParams params) {
    const bodyDependent = {4, 5, 6, 24, 25};
    var s = 0.0, ws = 0.0;
    for (var c = 0; c < size; c++) {
      if (bodyDependent.contains(c) || w8[c] == 0) continue;
      final d = math.min((a[c] - b[c]).abs(), params.featureClip);
      s += w8[c] * d * d;
      ws += w8[c];
    }
    return ws > 0 ? math.sqrt(s / ws) : 0;
  }

  /// Dispersión (RMS respecto a la mediana) de cada feature ya centrada.
  static List<double> _featureSpread(List<List<double>> f, int size) {
    final out = List<double>.filled(size, 0);
    for (final fr in f) {
      for (var c = 0; c < size; c++) {
        out[c] += fr[c] * fr[c];
      }
    }
    return [for (final v in out) math.sqrt(v / math.max(f.length, 1))];
  }

  static List<List<double>> _divided(
          List<List<double>> frames, List<double> scale) =>
      [
        for (final f in frames)
          List<double>.generate(f.length, (c) => f[c] / scale[c],
              growable: false),
      ];

  static List<double> _noiseFor(int size, DtwParams params) =>
      List<double>.generate(
          size,
          (c) => c < params.featureNoise.length
              ? params.featureNoise[c] * params.noiseScale
              : 0.0);

  /// Amplitud típica de cada feature: media de su desviación en ventanas.
  static List<double> _featureAmplitudes(
      List<List<double>> f, int size, int window) {
    final win = math.max(4, math.min(window, f.length));
    final out = List<double>.filled(size, 0);
    var count = 0;
    for (var s = 0; s + win <= f.length; s += win ~/ 2) {
      for (var c = 0; c < size; c++) {
        var mean = 0.0;
        for (var t = s; t < s + win; t++) {
          mean += f[t][c];
        }
        mean /= win;
        var v = 0.0;
        for (var t = s; t < s + win; t++) {
          final d = f[t][c] - mean;
          v += d * d;
        }
        out[c] += math.sqrt(v / win);
      }
      count++;
    }
    if (count > 0) {
      for (var c = 0; c < size; c++) {
        out[c] /= count;
      }
    }
    return out;
  }

  static List<List<double>> _scaled(
      List<List<double>> frames, int size, DtwParams params) {
    return [
      for (final f in frames)
        List<double>.generate(size, (c) {
          final range =
              c < params.featureRanges.length ? params.featureRanges[c] : 1.0;
          return f[c] / range;
        }, growable: false),
    ];
  }

  static List<double> _median(List<List<double>> frames, int size) {
    return List<double>.generate(size, (c) {
      final xs = [for (final f in frames) f[c]]..sort();
      return xs[xs.length ~/ 2];
    });
  }

  static List<List<double>> _centered(
      List<List<double>> frames, List<double> med) {
    return [
      for (final f in frames)
        List<double>.generate(f.length, (c) => f[c] - med[c], growable: false),
    ];
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

  /// Distancia euclídea ponderada entre dos vectores ya en unidades de rango.
  /// Cada diferencia se recorta a [DtwParams.featureClip]: un landmark
  /// perdido o una feature disparada un fotograma no debe pesar más que un
  /// error de verdad.
  static double _dist(List<double> v1, List<double> v2, int size,
      List<double> weights, double wsum, DtwParams params) {
    var sum = 0.0;
    final clip = params.featureClip;
    for (var i = 0; i < size; i++) {
      final wi = weights[i];
      if (wi == 0) continue;
      var diff = (v1[i] - v2[i]).abs();
      if (diff > clip) diff = clip;
      sum += wi * diff * diff;
    }
    return math.sqrt(sum / wsum);
  }
}
