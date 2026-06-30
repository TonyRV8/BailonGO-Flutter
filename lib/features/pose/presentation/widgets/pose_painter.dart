import 'package:flutter/material.dart';

import '../../domain/entities/pose_frame.dart';
import '../../domain/pose_landmarks.dart';

/// Dibuja el esqueleto sobre la preview (RF-09). MediaPipe devuelve coords
/// normalizadas 0..1 sobre la imagen ya vertical, así que el mapeo es directo;
/// para cámara frontal se espeja en X.
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
      final x = isFront ? (1.0 - lm.x) : lm.x;
      return Offset(x * size.width, lm.y * size.height);
    }

    // Huesos.
    for (final bone in PoseLandmarks.skeleton) {
      final a = at(bone[0]);
      final b = at(bone[1]);
      if (a != null && b != null) canvas.drawLine(a, b, linePaint);
    }

    // Puntos (rojo si es crítico y de baja confianza, RNF-05).
    for (final lm in frame.landmarks) {
      final x = isFront ? (1.0 - lm.x) : lm.x;
      final p = Offset(x * size.width, lm.y * size.height);
      final isCritLow = PoseLandmarks.lowerBodyCritical.contains(lm.type) &&
          lm.confidence < PoseLandmarks.minConfidence;
      canvas.drawCircle(p, 3, isCritLow ? critPaint : pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.frame != frame || old.isFront != isFront;
}
