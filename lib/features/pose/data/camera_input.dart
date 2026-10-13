import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Fotograma listo para MediaPipe: bytes NV21 + dimensiones + rotación a aplicar
/// para enderezar la imagen.
class CameraFrameData {
  const CameraFrameData({
    required this.nv21,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    this.mirrored = false,
  });

  final Uint8List nv21;
  final int width;
  final int height;
  final int rotationDegrees;

  /// La imagen viene espejada horizontalmente (cámara frontal en iOS) y el
  /// nativo debe des-espejarla para que coincida con Android.
  final bool mirrored;
}

/// Extrae los bytes NV21 de un [CameraImage] y calcula la rotación según el
/// sensor y la orientación del dispositivo. Devuelve `null` si el formato no es
/// NV21 de un solo plano.
///
/// Requiere inicializar la cámara con `ImageFormatGroup.nv21` (Android). En iOS
/// llega BGRA (`ImageFormatGroup.bgra8888`) y se reenvía tal cual.
CameraFrameData? cameraFrameFromImage({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  if (image.planes.length != 1) return null; // se espera NV21 empaquetado

  final sensorOrientation = camera.sensorOrientation;
  final int rotation;
  var mirrored = false;
  if (Platform.isIOS) {
    // camera_avfoundation ya aplica la orientación del dispositivo al stream
    // (videoOrientation) y espeja la cámara frontal (isVideoMirrored): el
    // fotograma llega derecho, solo falta deshacer el espejo.
    rotation = 0;
    mirrored = camera.lensDirection == CameraLensDirection.front;
  } else {
    final compensation = _orientations[deviceOrientation];
    if (compensation == null) return null;
    rotation = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
  }

  return CameraFrameData(
    nv21: image.planes.first.bytes,
    width: image.width,
    height: image.height,
    rotationDegrees: rotation,
    mirrored: mirrored,
  );
}
