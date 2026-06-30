/// Índices BlazePose (33 landmarks, doc 6.1) y agrupaciones usadas por las
/// reglas del documento.
class PoseLandmarks {
  PoseLandmarks._();

  // Tronco / brazos (subconjunto relevante).
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftHip = 23;
  static const int rightHip = 24;

  // Tren inferior.
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;

  /// Rodillas, tobillos y pies: si su confianza cae < 0.90 por > 1 s, el
  /// intento se invalida (RNF-05).
  static const List<int> lowerBodyCritical = [
    leftKnee,
    rightKnee,
    leftAnkle,
    rightAnkle,
    leftHeel,
    rightHeel,
    leftFootIndex,
    rightFootIndex,
  ];

  /// Conexiones del esqueleto para dibujar el overlay (pares de índices).
  static const List<List<int>> skeleton = [
    [leftShoulder, rightShoulder],
    [leftShoulder, leftHip],
    [rightShoulder, rightHip],
    [leftHip, rightHip],
    [leftHip, leftKnee],
    [leftKnee, leftAnkle],
    [leftAnkle, leftHeel],
    [leftHeel, leftFootIndex],
    [leftAnkle, leftFootIndex],
    [rightHip, rightKnee],
    [rightKnee, rightAnkle],
    [rightAnkle, rightHeel],
    [rightHeel, rightFootIndex],
    [rightAnkle, rightFootIndex],
  ];

  /// Umbral de confianza (RNF-05).
  static const double minConfidence = 0.90;
}
