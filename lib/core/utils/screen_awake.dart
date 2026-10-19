import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('bailongo/pose');

/// Mantiene la pantalla encendida mientras [on] es true: sin tocar el
/// teléfono, algunos equipos la oscurecen o bloquean a media evaluación.
/// Lo hace el código nativo del canal `bailongo/pose` (FLAG_KEEP_SCREEN_ON en
/// Android, `isIdleTimerDisabled` en iOS). Nunca falla: si la plataforma no
/// lo soporta simplemente no hace nada.
Future<void> keepScreenOn(bool on) async {
  try {
    await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
  } catch (_) {}
}
