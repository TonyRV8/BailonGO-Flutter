/// Resultado de la comparación DTW. Port 1:1 de `DTWResult` (Kotlin).
class DtwResult {
  const DtwResult({
    required this.score,
    required this.rhythmScore,
    required this.alignmentScore,
    required this.normalizedCost,
    required this.segmentRhythm,
    required this.segmentAlignment,
    required this.componentErrors,
    required this.worstComponentIndex,
    this.processingTimeMs = 0,
  });

  /// Precisión total 0..100 (RNF-06: 0.6*alineación + 0.4*ritmo).
  final int score;
  final int rhythmScore;
  final int alignmentScore;
  final double normalizedCost;
  final List<int> segmentRhythm;
  final List<int> segmentAlignment;
  final List<double> componentErrors;
  final int worstComponentIndex;
  final int processingTimeMs;

  /// Nombres de los 15 componentes del vector, para feedback cualitativo (RF-10).
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
  ];
}
