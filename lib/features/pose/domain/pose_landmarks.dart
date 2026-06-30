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

  /// Gate de validación (RNF-05): caderas, rodillas y tobillos. Si su confianza
  /// cae bajo [minConfidence] por > 1 s, el intento se invalida.
  ///
  /// Coincide con `CRITICAL_INDICES` del prototipo Kotlin. Los pies (talones y
  /// puntas) NO entran al gate duro: su visibilidad es naturalmente baja
  /// (prototipo usa 0.3) y su ausencia solo produce features de pie "neutras".
  static const List<int> lowerBodyCritical = [
    leftHip,
    rightHip,
    leftKnee,
    rightKnee,
    leftAnkle,
    rightAnkle,
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

  /// Umbral de confianza del gate (alineado al prototipo Kotlin:
  /// MIN_VISIBILITY = 0.5 para cadera/rodilla/tobillo).
  static const double minConfidence = 0.5;
}
