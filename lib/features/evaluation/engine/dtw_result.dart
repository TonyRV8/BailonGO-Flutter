/// Resultado de la comparación DTW. Port de `DTWResult` (Kotlin), extendido
/// con desglose por segmento (inicio/medio/final) para el feedback por tiempo.
class DtwResult {
  const DtwResult({
    required this.score,
    required this.rhythmScore,
    required this.alignmentScore,
    required this.normalizedCost,
    this.relativeCost = 0,
    this.coverage = 1,
    this.coverageFactor = 1,
    this.mirrorFactor = 1,
    this.pathDeviation = 0,
    this.segmentRelativeCost = const [],
    this.segmentFactor = const [],
    required this.segmentRhythm,
    required this.segmentAlignment,
    required this.segmentScore,
    required this.segmentTempo,
    required this.segmentComponentErrors,
    required this.segmentSignedErrors,
    required this.componentErrors,
    required this.worstComponentIndex,
    this.processingTimeMs = 0,
  });

  /// Precisión total 0..100 (RNF-06: 0.6*alineación + 0.4*ritmo).
  final int score;
  final int rhythmScore;
  final int alignmentScore;
  final double normalizedCost;

  /// Coste de alineación dividido por el de quedarse quieto frente a la misma
  /// referencia: 0 = idéntico, 1 = como no moverse.
  final double relativeCost;

  /// Fracción de la amplitud del modelo que el usuario cubrió (0..1).
  final double coverage;

  /// Multiplicadores aplicados por falta de movimiento y por lateralidad
  /// invertida (1 = sin castigo). Diagnóstico para el banco y el feedback.
  final double coverageFactor;
  final double mirrorFactor;

  /// Desviación media absoluta del camino DTW respecto a la diagonal,
  /// normalizada por max(n, m): cuánto hubo que deformar el tiempo para
  /// alinear al usuario. Diagnóstico.
  final double pathDeviation;

  /// Diagnóstico para el banco de calibración: coste relativo (ya con la
  /// postura media) y factor cobertura×espejo de cada tramo. Con ellos y
  /// [segmentRhythm] se puede recomputar la nota para otra curva de
  /// alineación sin repetir el DTW. Infinito = tramo sin fotogramas.
  final List<double> segmentRelativeCost;
  final List<double> segmentFactor;
  final List<int> segmentRhythm;
  final List<int> segmentAlignment;

  /// Precisión por segmento (RNF-06 aplicado a cada tiempo).
  final List<int> segmentScore;

  /// Desviación señada media del path por segmento, normalizada por
  /// max(n, m). Positiva = el usuario va adelantado respecto al modelo
  /// (ejecuta poses que llegan después) → debe ir más lento. Negativa =
  /// atrasado → debe ir más rápido.
  final List<double> segmentTempo;

  /// Error absoluto ponderado promedio por componente, por segmento
  /// (3 x featureSize). Sirve para localizar la peor feature de cada tiempo.
  final List<List<double>> segmentComponentErrors;

  /// Diferencia señada media (usuario − referencia, normalizada por rango)
  /// por componente y segmento. El signo da la dirección de la corrección
  /// ("levanta más" vs "no levantes tanto").
  final List<List<double>> segmentSignedErrors;

  final List<double> componentErrors;
  final int worstComponentIndex;
  final int processingTimeMs;

  /// Resultado vacío/cero seguro (entradas inválidas).
  static const DtwResult empty = DtwResult(
    score: 0,
    rhythmScore: 0,
    alignmentScore: 0,
    normalizedCost: 0,
    segmentRhythm: [0, 0, 0],
    segmentAlignment: [0, 0, 0],
    segmentScore: [0, 0, 0],
    segmentTempo: [0, 0, 0],
    segmentComponentErrors: [[], [], []],
    segmentSignedErrors: [[], [], []],
    componentErrors: [],
    worstComponentIndex: 0,
  );

  /// Nombres de los componentes del vector, para feedback cualitativo (RF-10).
  static const List<String> componentNames = [
    'la flexión de tu rodilla izquierda', // 0
    'la flexión de tu rodilla derecha', // 1
    'la inclinación de tu pierna izquierda', // 2
    'la inclinación de tu pierna derecha', // 3
    'la distancia entre tus pies', // 4
    'la altura de tu pie izquierdo', // 5
    'la altura de tu pie derecho', // 6
    'la posición lateral de tu pie izquierdo', // 7
    'la posición lateral de tu pie derecho', // 8
    'la posición lateral de tu rodilla izquierda', // 9
    'la posición lateral de tu rodilla derecha', // 10
    'la orientación de tu pie izquierdo', // 11
    'la orientación de tu pie derecho', // 12
    'la elevación de tu pie izquierdo', // 13
    'la elevación de tu pie derecho', // 14
    'la flexión de tu brazo izquierdo', // 15
    'la flexión de tu brazo derecho', // 16
    'la inclinación de tus hombros', // 17
    'la posición lateral de tu mano izquierda', // 18
    'la posición lateral de tu mano derecha', // 19
    'la altura de tu mano izquierda', // 20
    'la altura de tu mano derecha', // 21
    'la inclinación de tu cadera', // 22
    'el movimiento lateral de tu cadera', // 23
    'la altura de tu cadera', // 24
    'el giro de tu cadera', // 25
  ];
}
