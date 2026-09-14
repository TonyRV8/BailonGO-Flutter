import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../domain/entities/pose_frame.dart';
import '../domain/entities/pose_landmark.dart';
import '../domain/pose_landmarker.dart';

/// Implementación de [PoseLandmarker] sobre MediaPipe Tasks Vision a través de
/// un platform channel (ver `MainActivity.kt`). El nativo recibe NV21, corre
/// el modelo `pose_landmarker_lite.task` y devuelve un arreglo plano
/// [x, y, z, visibility] por cada uno de los 33 landmarks.
class MediaPipePoseLandmarker implements PoseLandmarker {
  static const MethodChannel _channel = MethodChannel('bailongo/pose');

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _channel.invokeMethod('init');
    _initialized = true;
  }

  @override
  Future<PoseFrame> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotationDegrees,
  }) async {
    // El nativo devuelve un DoubleArray, que el codec estándar entrega como
    // Float64List: sin envolver 132 Double por fotograma.
    final raw = await _channel.invokeMethod<Float64List>('detect', {
      'bytes': nv21,
      'width': width,
      'height': height,
      'rotation': rotationDegrees,
    });
    if (raw == null || raw.isEmpty) return PoseFrame.empty;

    final landmarks = List<PoseLandmark>.generate(
      raw.length ~/ 4,
      (i) => PoseLandmark(
        type: i,
        x: raw[i * 4],
        y: raw[i * 4 + 1],
        z: raw[i * 4 + 2],
        confidence: raw[i * 4 + 3],
      ),
      growable: false,
    );
    return PoseFrame(landmarks: landmarks);
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    await _channel.invokeMethod('close');
    _initialized = false;
  }
}
