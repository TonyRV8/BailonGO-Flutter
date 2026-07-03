import '../../../core/config/app_constants.dart';

/// Preferencias del usuario (campo `settings` del documento USERS).
class UserSettings {
  const UserSettings({
    this.learnedThreshold = AppConstants.learnedThreshold,
    this.mirrorCapture = false,
  });

  /// Umbral de "Paso Aprendido" (RN-02), en % de mejor precisión.
  final double learnedThreshold;

  /// Procesar la captura en vivo como espejada (corrige lateralidad invertida
  /// en dispositivos cuya cámara frontal entrega el frame ya volteado).
  final bool mirrorCapture;

  factory UserSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserSettings();
    return UserSettings(
      learnedThreshold: (map['learnedThreshold'] as num?)?.toDouble() ??
          AppConstants.learnedThreshold,
      mirrorCapture: (map['mirrorCapture'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'learnedThreshold': learnedThreshold,
        'mirrorCapture': mirrorCapture,
      };

  UserSettings copyWith({double? learnedThreshold, bool? mirrorCapture}) {
    return UserSettings(
      learnedThreshold: learnedThreshold ?? this.learnedThreshold,
      mirrorCapture: mirrorCapture ?? this.mirrorCapture,
    );
  }
}
