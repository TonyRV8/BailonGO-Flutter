/// Parámetros de ajuste del motor de evaluación.
///
/// Existen para poder BARRER valores desde el banco de escenarios
/// (`tool/bench.dart`) sin duplicar el algoritmo: `DtwComparator.compare` usa
/// `DtwParams.defaults` salvo que se le pase otro juego.
///
/// Revisión 2 (2026-09-17): la curva de alineación trabaja sobre el COSTE
/// RELATIVO (coste / coste de quedarse quieto), una escala común a todos los
/// pasos. Ver la cabecera de `DtwComparator` para el porqué de cada bloque.
class DtwParams {
  const DtwParams({
    this.alignNoiseFloor = 0.2,
    this.alignMax = 1.2,
    this.alignCurvePower = 0.8,
    this.bandRatio = 0.12,
    this.smoothWindow = 5,
    this.centerFeatures = true,
    this.featureClip = 2.0,
    this.offsetWeight = 0.05,
    this.minMotion = 0.02,
    this.featureNoise = defaultFeatureNoise,
    this.noiseScale = 1.0,
    this.snrK = 8.0,
    this.amplitudeNormalize = true,
    this.amplitudeNoiseMul = 3.0,
    this.alignWeight = 0.6,
    this.rhythmWeight = 0.4,
    this.coverageWindow = 30,
    this.coverageIgnoreBelow = 0.3,
    this.coverageFullRatio = 0.45,
    this.coverageZeroRatio = 0.25,
    this.coverageMinFactor = 0.0,
    this.rhythmWindow = 60,
    this.rhythmMaxLag = 8,
    this.rhythmSmooth = 5,
    this.rhythmCorrZero = 0.0,
    this.rhythmCorrFull = 0.3,
    this.globalFromSegments = true,
    this.mirrorFullSeverity = 0.35,
    this.mirrorMinFactor = 0.15,
    this.featureRanges = defaultFeatureRanges,
  });

  /// Juego vigente en producción.
  static const DtwParams defaults = DtwParams();

  /// Coste relativo ≤ esto → alineación 100 %.
  final double alignNoiseFloor;

  /// Coste relativo ≥ esto → alineación 0 %. 1.0 = tan lejos como no moverse.
  final double alignMax;

  /// Exponente de la curva coste→score (>1 castiga diferencias medianas).
  final double alignCurvePower;

  /// Banda Sakoe-Chiba: máximo desfase como fracción de max(n, m).
  final double bandRatio;

  /// Ventana centrada para suavizado pre-DTW (fotogramas).
  final int smoothWindow;

  /// Restar la mediana de cada feature antes de comparar (movimiento, no
  /// complexión). La postura media entra aparte con [offsetWeight].
  final bool centerFeatures;

  /// Tope de la diferencia por feature, en unidades de rango.
  final double featureClip;

  /// Peso de la diferencia de postura media dentro del coste relativo.
  final double offsetWeight;

  /// Amplitud mínima (unidades de rango) que se considera movimiento: evita
  /// dividir por casi cero en referencias con tramos quietos.
  final double minMotion;

  /// Temblor típico del detector en vivo por feature (unidades de rango, tras
  /// suavizar), multiplicado por [noiseScale]. Sirve para dos cosas: bajar el
  /// peso de las features que en un paso se mueven menos que el temblor
  /// (peso x a²/(a² + [snrK]·ruido²), con `a` la amplitud de la referencia) y
  /// descontar ese temblor al medir cuánto se movió el usuario.
  final List<double> featureNoise;
  final double noiseScale;
  final double snrK;

  /// Medir cada feature en unidades de su propia dispersión en la referencia
  /// (con un mínimo de [amplitudeNoiseMul] × temblor), en vez de su rango
  /// global. Ver `DtwComparator.compare`.
  final bool amplitudeNormalize;
  final double amplitudeNoiseMul;

  /// Medido con `dart run tool/bench.dart tool/landmarks.json --snr` sobre el
  /// escenario "quieto" (cámara 480x720, temblor ~3x el de las tomas). Las más
  /// ruidosas son las que dividen dos distancias pequeñas en vertical: pitch
  /// del pie (13,14), inclinación de hombros (17) y de cadera (22).
  static const List<double> defaultFeatureNoise = [
    0.0109, 0.0135, 0.0019, 0.0028, 0.0057, 0.0038, 0.0035, 0.0061, 0.0062,
    0.0049, 0.0042, 0.0054, 0.0052, 0.0305, 0.0305, 0.0041, 0.0040, 0.0175,
    0.0029, 0.0021, 0.0050, 0.0045, 0.0596, 0.0110, 0.0020, 0.0190,
  ];

  /// Pesos alineación vs ritmo (RNF-06). Fijados por el documento: no se
  /// barren en la calibración.
  final double alignWeight;
  final double rhythmWeight;

  /// Cobertura: ventana (fotogramas) en la que se compara la amplitud del
  /// usuario con la del modelo, ventanas del modelo más quietas que
  /// [coverageIgnoreBelow] × la mediana que no cuentan, y rampa ratio→factor.
  final int coverageWindow;
  final double coverageIgnoreBelow;
  final double coverageFullRatio;
  final double coverageZeroRatio;
  final double coverageMinFactor;

  /// Ritmo: ventana de correlación (fotogramas), margen de reacción (± lag),
  /// suavizado del perfil de velocidad y rampa correlación→score.
  final int rhythmWindow;
  final int rhythmMaxLag;
  final int rhythmSmooth;
  final double rhythmCorrZero;
  final double rhythmCorrFull;

  /// La nota global es la media de los tres tramos (inicio/medio/final).
  final bool globalFromSegments;

  /// Detección de ejecución especular.
  final double mirrorFullSeverity;
  final double mirrorMinFactor;

  /// Divisor de normalización por feature: cuánto tiene que cambiar cada una
  /// para contar como 1.0 de distancia.
  final List<double> featureRanges;

  /// Divisor por feature, RE-DERIVADO DE LOS DATOS (2026-09-13).
  ///
  /// Los valores originales venían del prototipo Kotlin, calibrado sobre un
  /// baile de brazos, y estaban muy mal escalados para los pasos de piernas:
  /// la orientación del pie (11,12) tenía rango 2.0 cuando en el corpus real
  /// se mueve 3.56 (quedaba amplificada 3.6x), y la inclinación de hombros
  /// (17) tenía rango 3.0 con una dispersión real de 0.26 (quedaba muda). El
  /// efecto era que el `normalizedCost` variaba 30x entre pasos (0.027 a
  /// 0.855) y ningún par global (noiseFloor, max) podía mapearlos todos a la
  /// banda objetivo.
  ///
  /// Cada rango es 2x la dispersión observada (p95-p5) de esa feature sobre
  /// los 9 videos ideales. Re-medidos el 2026-09-17 con la corrección de
  /// aspecto (las features con componente vertical crecieron ~1.8x). Las de
  /// cadera (22-25) se añadieron en la 3a vuelta; la 23 (desplazamiento lateral) resultó ser la feature MÁS discriminativa
  /// del vector: separa la toma buena de la regular en un 84 % de su propia
  /// dispersión, frente al 21 % del ángulo de rodilla. Regenerable con:
  ///   dart run tool/bench.dart tool/landmarks.json --ranges
  static const List<double> defaultFeatureRanges = [
    84.12, // 0  ángulo rodilla izquierda
    84.21, // 1  ángulo rodilla derecha
    0.287, // 2  inclinación pierna izquierda
    0.298, // 3  inclinación pierna derecha
    7.072, // 4  distancia entre tobillos
    24.0, // 5  altura Y tobillo izquierdo
    25.45, // 6  altura Y tobillo derecho
    4.91, // 7  X tobillo izquierdo
    4.68, // 8  X tobillo derecho
    3.767, // 9  X rodilla izquierda
    4.201, // 10 X rodilla derecha
    7.163, // 11 dirección X pie izquierdo
    7.271, // 12 dirección X pie derecho
    1.894, // 13 pitch pie izquierdo
    1.916, // 14 pitch pie derecho
    341.13, // 15 ángulo brazo izquierdo
    347.41, // 16 ángulo brazo derecho
    0.917, // 17 inclinación de hombros
    4.041, // 18 X muñeca izquierda
    5.823, // 19 X muñeca derecha
    4.524, // 20 Y muñeca izquierda
    4.837, // 21 Y muñeca derecha
    0.482, // 22 inclinación de cadera
    0.706, // 23 desplazamiento lateral de cadera
    9.805, // 24 altura de cadera
    0.671, // 25 rotación de cadera
  ];


  DtwParams copyWith({
    double? alignNoiseFloor,
    double? alignMax,
    double? alignCurvePower,
    double? bandRatio,
    int? smoothWindow,
    bool? centerFeatures,
    double? featureClip,
    double? offsetWeight,
    double? minMotion,
    double? noiseScale,
    double? snrK,
    bool? amplitudeNormalize,
    double? amplitudeNoiseMul,
    int? coverageWindow,
    double? coverageIgnoreBelow,
    double? coverageFullRatio,
    double? coverageZeroRatio,
    double? coverageMinFactor,
    int? rhythmWindow,
    int? rhythmMaxLag,
    int? rhythmSmooth,
    double? rhythmCorrZero,
    double? rhythmCorrFull,
    bool? globalFromSegments,
    double? mirrorFullSeverity,
    double? mirrorMinFactor,
    List<double>? featureRanges,
  }) =>
      DtwParams(
        alignNoiseFloor: alignNoiseFloor ?? this.alignNoiseFloor,
        alignMax: alignMax ?? this.alignMax,
        alignCurvePower: alignCurvePower ?? this.alignCurvePower,
        bandRatio: bandRatio ?? this.bandRatio,
        smoothWindow: smoothWindow ?? this.smoothWindow,
        centerFeatures: centerFeatures ?? this.centerFeatures,
        featureClip: featureClip ?? this.featureClip,
        offsetWeight: offsetWeight ?? this.offsetWeight,
        minMotion: minMotion ?? this.minMotion,
        featureNoise: featureNoise,
        noiseScale: noiseScale ?? this.noiseScale,
        snrK: snrK ?? this.snrK,
        amplitudeNormalize: amplitudeNormalize ?? this.amplitudeNormalize,
        amplitudeNoiseMul: amplitudeNoiseMul ?? this.amplitudeNoiseMul,
        alignWeight: alignWeight,
        rhythmWeight: rhythmWeight,
        coverageWindow: coverageWindow ?? this.coverageWindow,
        coverageIgnoreBelow: coverageIgnoreBelow ?? this.coverageIgnoreBelow,
        coverageFullRatio: coverageFullRatio ?? this.coverageFullRatio,
        coverageZeroRatio: coverageZeroRatio ?? this.coverageZeroRatio,
        coverageMinFactor: coverageMinFactor ?? this.coverageMinFactor,
        rhythmWindow: rhythmWindow ?? this.rhythmWindow,
        rhythmMaxLag: rhythmMaxLag ?? this.rhythmMaxLag,
        rhythmSmooth: rhythmSmooth ?? this.rhythmSmooth,
        rhythmCorrZero: rhythmCorrZero ?? this.rhythmCorrZero,
        rhythmCorrFull: rhythmCorrFull ?? this.rhythmCorrFull,
        globalFromSegments: globalFromSegments ?? this.globalFromSegments,
        mirrorFullSeverity: mirrorFullSeverity ?? this.mirrorFullSeverity,
        mirrorMinFactor: mirrorMinFactor ?? this.mirrorMinFactor,
        featureRanges: featureRanges ?? this.featureRanges,
      );

  @override
  String toString() => 'DtwParams('
      'nf ${alignNoiseFloor.toStringAsFixed(3)}, '
      'max ${alignMax.toStringAsFixed(3)}, '
      'pow ${alignCurvePower.toStringAsFixed(2)}, '
      'band ${bandRatio.toStringAsFixed(2)}, '
      'center $centerFeatures, clip $featureClip, off $offsetWeight, '
      'noise x$noiseScale k$snrK, ampNorm $amplitudeNormalize x$amplitudeNoiseMul, '
      'cov ${coverageZeroRatio.toStringAsFixed(2)}/${coverageFullRatio.toStringAsFixed(2)}'
      '@${coverageMinFactor.toStringAsFixed(2)} w$coverageWindow, '
      'rhy ${rhythmCorrZero.toStringAsFixed(2)}/${rhythmCorrFull.toStringAsFixed(2)} '
      'w$rhythmWindow lag$rhythmMaxLag)';
}
