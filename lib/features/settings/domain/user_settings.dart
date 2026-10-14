import '../../../core/config/app_constants.dart';

/// Preferencias del usuario (campo `settings` del documento USERS).
class UserSettings {
  const UserSettings({
    this.learnedThreshold = AppConstants.learnedThreshold,
    this.mirrorCapture = false,
    this.autoStartOnStill = true,
    this.showCues = true,
  });

  /// Umbral de "Paso Aprendido" (RN-02), en % de mejor precisión.
  final double learnedThreshold;

  /// Procesar la captura en vivo como espejada (corrige lateralidad invertida
  /// en dispositivos cuya cámara frontal entrega el frame ya volteado).
  final bool mirrorCapture;

  /// Arrancar la cuenta regresiva automaticamente tras
  /// [AppConstants.stillnessSeconds] s quieto y ya encuadrado (RF-08.3). Si se
  /// desactiva, solo arranca con el gesto de brazos arriba o con el boton.
  final bool autoStartOnStill;

  /// Mostrar las flechas guía sobre la cámara durante el intento. Se puede
  /// apagar para evaluar sin ayudas.
  final bool showCues;

  factory UserSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserSettings();
    return UserSettings(
      learnedThreshold: (map['learnedThreshold'] as num?)?.toDouble() ??
          AppConstants.learnedThreshold,
      mirrorCapture: (map['mirrorCapture'] as bool?) ?? false,
      autoStartOnStill: (map['autoStartOnStill'] as bool?) ?? true,
      showCues: (map['showCues'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'learnedThreshold': learnedThreshold,
        'mirrorCapture': mirrorCapture,
        'autoStartOnStill': autoStartOnStill,
        'showCues': showCues,
      };

  UserSettings copyWith({
    double? learnedThreshold,
    bool? mirrorCapture,
    bool? autoStartOnStill,
    bool? showCues,
  }) {
    return UserSettings(
      learnedThreshold: learnedThreshold ?? this.learnedThreshold,
      mirrorCapture: mirrorCapture ?? this.mirrorCapture,
      autoStartOnStill: autoStartOnStill ?? this.autoStartOnStill,
      showCues: showCues ?? this.showCues,
    );
  }
}
