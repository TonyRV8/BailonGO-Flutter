/// Constantes globales de la app (no secretas).
class AppConstants {
  AppConstants._();

  static const String appName = 'BailonGO';

  // Nombres de colecciones Firestore (doc 5.3.3 / Figura 7).
  static const String usersCollection = 'users';
  static const String catalogCollection = 'catalog';
  static const String referenceDataCollection = 'reference_data';
  static const String historyCollection = 'history';
  static const String globalMetricsCollection = 'global_metrics';

  // Reglas de negocio del documento (referencia, se usan en fases posteriores).
  static const double precisionWeightAlignment = 0.6; // RNF-06
  static const double precisionWeightRhythm = 0.4; // RNF-06
  static const int countdownSeconds = 3; // RF-08

  /// Segundos quieto y encuadrado para que la evaluacion arranque sola
  /// (RF-08.3, desactivable en Configuracion).
  static const int stillnessSeconds = 2;

  /// Mezcla del intento cuando el paso tiene voz guía: la voz manda (conteo e
  /// instrucciones claras) y la música queda de fondo marcando el ritmo.
  /// Sin voz, la música suena a [musicSoloVolume].
  static const double voiceGuideVolume = 1.0;
  static const double musicUnderVoiceVolume = 0.75;
  static const double musicSoloVolume = 1.0;

  /// Umbral de "Paso Aprendido" (RN-02): mejor precisión ≥ esto. Pendiente de
  /// calibrar (plan.txt §8); configurable a futuro.
  static const double learnedThreshold = 80; // %
}
