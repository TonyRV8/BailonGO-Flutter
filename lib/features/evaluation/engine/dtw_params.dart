/// Parámetros de ajuste del motor de evaluación.
///
/// Existen para poder BARRER valores desde el banco de calibración
/// (`tool/calibrate.dart`) sin duplicar el algoritmo: `DtwComparator.compare`
/// usa `DtwParams.defaults` salvo que se le pase otro juego. Los valores por
/// defecto son exactamente los `const val` heredados del prototipo Kotlin, así
/// que el comportamiento de la app no cambia mientras nadie pase `params`.
///
/// Al terminar la calibración, los valores ganadores se escriben aquí como
/// nuevos defaults (implementar_pasos.txt §7.6).
class DtwParams {
  const DtwParams({
    this.alignNoiseFloor = 0.09,
    this.alignMax = 0.19,
    this.alignCurvePower = 2.0,
    this.bandRatio = 0.12,
    this.smoothWindow = 5,
    this.rhythmFullDev = 0.04,
    this.rhythmZeroDev = 0.25,
    this.alignWeight = 0.6,
    this.rhythmWeight = 0.4,
    this.coverageFullRatio = 0.75,
    this.coverageZeroRatio = 0.25,
    this.coverageMinFactor = 0.4,
    this.mirrorFullSeverity = 0.35,
    this.mirrorMinFactor = 0.15,
    this.featureRanges = defaultFeatureRanges,
  });

  /// Juego vigente en producción.
  static const DtwParams defaults = DtwParams();

  /// Zona muerta: costo promedio ≤ esto → alineación 100%.
  final double alignNoiseFloor;

  /// Costo promedio ≥ esto → alineación 0%.
  final double alignMax;

  /// Exponente de la curva costo→score (>1 castiga diferencias medianas).
  final double alignCurvePower;

  /// Banda Sakoe-Chiba: máximo desfase como fracción de max(n, m).
  final double bandRatio;

  /// Ventana centrada para suavizado pre-DTW.
  final int smoothWindow;

  /// Ritmo: desviación del path respecto a la diagonal ideal.
  final double rhythmFullDev;
  final double rhythmZeroDev;

  /// Pesos alineación vs ritmo (RNF-06). Fijados por el documento: no se
  /// barren en la calibración.
  final double alignWeight;
  final double rhythmWeight;

  /// Cobertura de movimiento (detecta ejecución incompleta).
  final double coverageFullRatio;
  final double coverageZeroRatio;
  final double coverageMinFactor;

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
  /// los 9 videos ideales. Las de cadera (22-25) se añadieron en la 3a vuelta;
  /// la 23 (desplazamiento lateral) resultó ser la feature MÁS discriminativa
  /// del vector: separa la toma buena de la regular en un 84 % de su propia
  /// dispersión, frente al 21 % del ángulo de rodilla. Regenerable con:
  ///   dart run tool/calibrate.dart <landmarks.json> --stats
  static const List<double> defaultFeatureRanges = [
    128.22, // 0  ángulo rodilla izquierda
    129.78, // 1  ángulo rodilla derecha
    0.64, //   2  inclinación pierna izquierda
    0.65, //   3  inclinación pierna derecha
    6.59, //   4  distancia entre tobillos
    13.39, //  5  altura Y tobillo izquierdo
    14.25, //  6  altura Y tobillo derecho
    4.87, //   7  X tobillo izquierdo
    4.69, //   8  X tobillo derecho
    3.83, //   9  X rodilla izquierda
    4.17, //   10 X rodilla derecha
    7.13, //   11 dirección X pie izquierdo
    7.12, //   12 dirección X pie derecho
    1.07, //   13 pitch pie izquierdo
    1.08, //   14 pitch pie derecho
    330.75, // 15 ángulo brazo izquierdo
    342.36, // 16 ángulo brazo derecho
    0.52, //   17 inclinación de hombros
    3.99, //   18 X muñeca izquierda
    5.82, //   19 X muñeca derecha
    2.55, //   20 Y muñeca izquierda
    2.76, //   21 Y muñeca derecha
    0.27, //   22 inclinación de cadera
    0.70, //   23 desplazamiento lateral de cadera
    5.72, //   24 altura de cadera
    0.71, //   25 rotación de cadera
  ];


  DtwParams copyWith({
    double? alignNoiseFloor,
    double? alignMax,
    double? alignCurvePower,
    double? bandRatio,
    int? smoothWindow,
    double? rhythmFullDev,
    double? rhythmZeroDev,
    double? coverageFullRatio,
    double? coverageZeroRatio,
    double? coverageMinFactor,
    double? mirrorFullSeverity,
    double? mirrorMinFactor,
  }) =>
      DtwParams(
        alignNoiseFloor: alignNoiseFloor ?? this.alignNoiseFloor,
        alignMax: alignMax ?? this.alignMax,
        alignCurvePower: alignCurvePower ?? this.alignCurvePower,
        bandRatio: bandRatio ?? this.bandRatio,
        smoothWindow: smoothWindow ?? this.smoothWindow,
        rhythmFullDev: rhythmFullDev ?? this.rhythmFullDev,
        rhythmZeroDev: rhythmZeroDev ?? this.rhythmZeroDev,
        alignWeight: alignWeight,
        rhythmWeight: rhythmWeight,
        coverageFullRatio: coverageFullRatio ?? this.coverageFullRatio,
        coverageZeroRatio: coverageZeroRatio ?? this.coverageZeroRatio,
        coverageMinFactor: coverageMinFactor ?? this.coverageMinFactor,
        mirrorFullSeverity: mirrorFullSeverity ?? this.mirrorFullSeverity,
        mirrorMinFactor: mirrorMinFactor ?? this.mirrorMinFactor,
        featureRanges: featureRanges,
      );

  @override
  String toString() => 'DtwParams('
      'noiseFloor: ${alignNoiseFloor.toStringAsFixed(3)}, '
      'max: ${alignMax.toStringAsFixed(3)}, '
      'power: ${alignCurvePower.toStringAsFixed(2)}, '
      'band: ${bandRatio.toStringAsFixed(2)}, '
      'smooth: $smoothWindow, '
      'rhythm: ${rhythmFullDev.toStringAsFixed(3)}/${rhythmZeroDev.toStringAsFixed(3)}, '
      'cov: ${coverageZeroRatio.toStringAsFixed(2)}/${coverageFullRatio.toStringAsFixed(2)}'
      '@${coverageMinFactor.toStringAsFixed(2)})';
}
