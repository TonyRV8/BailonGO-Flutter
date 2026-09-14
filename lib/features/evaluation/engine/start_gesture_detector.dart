import '../../pose/domain/entities/pose_frame.dart';
import '../../pose/domain/pose_landmarks.dart';

/// Estado del armado previo a la cuenta regresiva (RF-08.1..08.5).
enum ArmingState {
  /// No se detecta ningún cuerpo.
  noBody,

  /// Hay cuerpo, pero el tren inferior no cumple el gate de RNF-05: el usuario
  /// está demasiado cerca o recortado.
  outOfFrame,

  /// Encuadre correcto; esperando la señal del usuario.
  waiting,

  /// Brazos por encima de los hombros, acumulando la ventana de confirmación.
  raisingArms,

  /// Encuadrado y sin moverse, acumulando la ventana de quietud.
  holdingStill,
}

/// Qué disparó el arranque de la cuenta regresiva.
enum StartTrigger { none, arms, stillness }

/// Lectura de un fotograma durante la fase de armado.
class ArmingStatus {
  const ArmingStatus(
    this.state, {
    this.progress = 0,
    this.trigger = StartTrigger.none,
  });

  final ArmingState state;

  /// Avance 0..1 de la ventana de confirmación en curso (brazos o quietud).
  final double progress;

  final StartTrigger trigger;

  bool get isTriggered => trigger != StartTrigger.none;
}

/// Decide cuándo arranca la cuenta regresiva sin que el usuario toque el
/// teléfono (RF-08.1..08.5). Dos disparadores, ambos sobre los 33 landmarks que
/// el pipeline de pose ya calcula por fotograma:
///
/// * **Brazos arriba**: ambas muñecas por encima de la línea de los hombros,
///   sostenido [armsHold]. Es el gesto explícito y el más rápido.
/// * **Quietud**: el usuario permanece encuadrado y sin desplazarse durante
///   [stillnessHold]. Opcional ([stillnessEnabled]).
///
/// Precondición común: los landmarks críticos de RNF-05 (caderas, rodillas y
/// tobillos) visibles. Así la captura nunca empieza con el usuario a medio
/// encuadrar, que es justo lo que invalidaba intentos.
///
/// Las coordenadas llegan normalizadas 0..1 sobre la imagen ya vertical y con
/// el eje Y creciendo hacia ABAJO (ver [PoseFrame]), por lo que "por encima de"
/// se traduce en `y` MENOR.
class StartGestureDetector {
  StartGestureDetector({
    this.stillnessEnabled = true,
    this.armsHold = const Duration(milliseconds: 400),
    this.stillnessHold = const Duration(seconds: 2),
    this.warmup = const Duration(milliseconds: 1500),
    this.marginY = 0.06,
    this.stillnessTolerance = 0.035,
  });

  /// Permite arrancar quedándose quieto. Se controla desde Configuración.
  bool stillnessEnabled;

  /// Cuánto hay que mantener los brazos arriba para confirmar el gesto.
  final Duration armsHold;

  /// Cuánto hay que permanecer quieto para que arranque solo.
  final Duration stillnessHold;

  /// Margen de cortesía tras entrar en armado antes de considerar la quietud:
  /// evita que se dispare mientras el usuario aún camina hacia su sitio.
  final Duration warmup;

  /// Cuánto debe superar la muñeca a la línea de hombros (fracción de alto).
  final double marginY;

  /// Desplazamiento máximo tolerado (fracción del encuadre) para seguir
  /// contando como "quieto".
  final double stillnessTolerance;

  /// Puntos que se vigilan para decidir si el usuario está quieto. Incluye el
  /// tren inferior para que dar un paso rompa la quietud aunque el torso no se
  /// mueva.
  static const List<int> _stillnessPoints = [
    PoseLandmarks.leftShoulder,
    PoseLandmarks.rightShoulder,
    PoseLandmarks.leftHip,
    PoseLandmarks.rightHip,
    PoseLandmarks.leftKnee,
    PoseLandmarks.rightKnee,
    PoseLandmarks.leftAnkle,
    PoseLandmarks.rightAnkle,
  ];

  /// Umbral por debajo del cual no se anuncia la quietud todavía: sin esto, el
  /// overlay diría "quieto…" en cada fotograma en que el usuario se mueve.
  static const double _stillnessVisibleFrom = 0.15;

  DateTime? _startedAt;
  DateTime? _armsSince;
  DateTime? _stillSince;
  Map<int, ({double x, double y})>? _anchor;

  /// Reinicia el detector al entrar en la fase de armado.
  void start([DateTime? now]) {
    reset();
    _startedAt = now ?? DateTime.now();
  }

  void reset() {
    _startedAt = null;
    _armsSince = null;
    _stillSince = null;
    _anchor = null;
  }

  ArmingStatus update(PoseFrame frame, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _startedAt ??= t;

    if (!frame.hasBody) {
      _clearHolds();
      return const ArmingStatus(ArmingState.noBody);
    }
    if (!_lowerBodyVisible(frame)) {
      _clearHolds();
      return const ArmingStatus(ArmingState.outOfFrame);
    }

    // (A) Gesto explícito: brazos arriba. Tiene prioridad sobre la quietud.
    if (_armsRaised(frame)) {
      _stillSince = null;
      _anchor = null;
      _armsSince ??= t;
      final held = t.difference(_armsSince!);
      if (held >= armsHold) {
        _clearHolds();
        return const ArmingStatus(ArmingState.raisingArms,
            progress: 1, trigger: StartTrigger.arms);
      }
      return ArmingStatus(ArmingState.raisingArms,
          progress: _ratio(held, armsHold));
    }
    _armsSince = null;

    // (E) Arranque automático al quedarse quieto, ya encuadrado.
    if (stillnessEnabled && t.difference(_startedAt!) >= warmup) {
      if (_anchor == null || _movedFromAnchor(frame)) {
        _anchor = _snapshot(frame);
        _stillSince = t;
      }
      final held = t.difference(_stillSince ?? t);
      if (held >= stillnessHold) {
        _clearHolds();
        return const ArmingStatus(ArmingState.holdingStill,
            progress: 1, trigger: StartTrigger.stillness);
      }
      final progress = _ratio(held, stillnessHold);
      if (progress >= _stillnessVisibleFrom) {
        return ArmingStatus(ArmingState.holdingStill, progress: progress);
      }
      return const ArmingStatus(ArmingState.waiting);
    }
    _stillSince = null;
    _anchor = null;
    return const ArmingStatus(ArmingState.waiting);
  }

  void _clearHolds() {
    _armsSince = null;
    _stillSince = null;
    _anchor = null;
  }

  double _ratio(Duration held, Duration target) =>
      (held.inMilliseconds / target.inMilliseconds).clamp(0.0, 1.0);

  /// Gate de encuadre (RNF-05): caderas, rodillas y tobillos visibles.
  bool _lowerBodyVisible(PoseFrame frame) {
    for (final type in PoseLandmarks.lowerBodyCritical) {
      final lm = frame.byType(type);
      if (lm == null || lm.confidence < PoseLandmarks.minConfidence) {
        return false;
      }
    }
    return true;
  }

  /// Ambas muñecas por encima de la línea de hombros. Se exigen las DOS para no
  /// confundirlo con un movimiento casual; al ser simétrico, `mirrorCapture` no
  /// le afecta.
  bool _armsRaised(PoseFrame frame) {
    final ls = frame.byType(PoseLandmarks.leftShoulder);
    final rs = frame.byType(PoseLandmarks.rightShoulder);
    final lw = frame.byType(PoseLandmarks.leftWrist);
    final rw = frame.byType(PoseLandmarks.rightWrist);
    if (ls == null || rs == null || lw == null || rw == null) return false;
    const min = PoseLandmarks.minConfidence;
    if (ls.confidence < min || rs.confidence < min) return false;
    if (lw.confidence < min || rw.confidence < min) return false;
    final shoulderY = (ls.y + rs.y) / 2;
    // Si la muñeca sale por el borde superior, MediaPipe la extrapola con y < 0
    // y la condición se cumple igual: el caso recortado juega a favor.
    return lw.y < shoulderY - marginY && rw.y < shoulderY - marginY;
  }

  Map<int, ({double x, double y})> _snapshot(PoseFrame frame) {
    final out = <int, ({double x, double y})>{};
    for (final type in _stillnessPoints) {
      final lm = frame.byType(type);
      if (lm != null && lm.confidence >= PoseLandmarks.minConfidence) {
        out[type] = (x: lm.x, y: lm.y);
      }
    }
    return out;
  }

  /// True si algún punto vigilado se alejó de su posición de referencia más de
  /// [stillnessTolerance], o si dejó de verse.
  bool _movedFromAnchor(PoseFrame frame) {
    final anchor = _anchor;
    if (anchor == null || anchor.isEmpty) return true;
    for (final entry in anchor.entries) {
      final lm = frame.byType(entry.key);
      if (lm == null || lm.confidence < PoseLandmarks.minConfidence) {
        return true;
      }
      final dx = lm.x - entry.value.x;
      final dy = lm.y - entry.value.y;
      if (dx * dx + dy * dy > stillnessTolerance * stillnessTolerance) {
        return true;
      }
    }
    return false;
  }
}
