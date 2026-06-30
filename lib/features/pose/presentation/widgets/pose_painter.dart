import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../domain/entities/pose_frame.dart';
import '../../domain/pose_landmarks.dart';

/// Dibuja el esqueleto sobre la preview de la cámara (RF-09). El mapeo de
/// coordenadas imagen->canvas sigue el patrón oficial de google_mlkit_example
/// (maneja rotación y espejo de cámara frontal).
class PosePainter extends CustomPainter {
  PosePainter({required this.frame, required this.isFront});

  final PoseFrame frame;
  final bool isFront;

  @override
  void paint(Canvas canvas, Size size) {
    if (!frame.hasBody) return;

    final pointPaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final critPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 3;

    Offset? at(int type) {
      final lm = frame.byType(type);
      if (lm == null) return null;
      return Offset(
        _translateX(lm.x, size),
        _translateY(lm.y, size),
      );
    }

    // Huesos.
    for (final bone in PoseLandmarks.skeleton) {
      final a = at(bone[0]);
      final b = at(bone[1]);
      if (a != null && b != null) canvas.drawLine(a, b, linePaint);
    }

    // Puntos (rojo si es crítico y de baja confianza, RNF-05).
    for (final lm in frame.landmarks) {
      final p = Offset(_translateX(lm.x, size), _translateY(lm.y, size));
      final isCritLow = PoseLandmarks.lowerBodyCritical.contains(lm.type) &&
          lm.confidence < PoseLandmarks.minConfidence;
      canvas.drawCircle(p, 3, isCritLow ? critPaint : pointPaint);
    }
  }

  double _imgW() =>
      Platform.isIOS ? frame.imageSize.width : frame.imageSize.height;
  double _imgH() =>
      Platform.isIOS ? frame.imageSize.height : frame.imageSize.width;

  double _translateX(double x, Size canvas) {
    switch (frame.rotationDegrees) {
      case 90:
        return x * canvas.width / _imgW();
      case 270:
        return canvas.width - x * canvas.width / _imgW();
      default: // 0 / 180
        final v = x * canvas.width / frame.imageSize.width;
        return isFront ? canvas.width - v : v;
    }
  }

  double _translateY(double y, Size canvas) {
    switch (frame.rotationDegrees) {
      case 90:
      case 270:
        return y * canvas.height / _imgH();
      default: // 0 / 180
        return y * canvas.height / frame.imageSize.height;
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.frame != frame || old.isFront != isFront;
}
