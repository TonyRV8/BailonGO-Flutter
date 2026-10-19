import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../evaluation/engine/start_gesture_detector.dart';
import '../../../evaluation/presentation/widgets/arming_overlay.dart';
import '../../../pose/domain/entities/pose_frame.dart';
import '../../../pose/domain/pose_landmarks.dart';
import '../../../pose/presentation/widgets/pose_painter.dart';
import '../../domain/tutorial_figure.dart';

/// Lo que se superpone a la "cámara" simulada.
enum MockOverlay {
  /// Avisos de encuadre y gesto de inicio (los mismos de la evaluación).
  arming,

  /// Sin avisos (cuenta regresiva arrancando, o mientras se señala la
  /// cámara).
  starting,

  /// Resultado abierto con el recordatorio del gesto de reintento.
  results,
}

/// Pantalla del teléfono durante una evaluación, simulada: la persona (una
/// silueta) vista por la cámara frontal, con el MISMO esqueleto ([PosePainter])
/// y los MISMOS avisos ([ArmingOverlay]) que verá el usuario de verdad.
///
/// Se pinta a tamaño de teléfono (360×740 lógicos) y se escala para caber, así
/// los textos de los avisos guardan sus proporciones reales.
class MockCamera extends StatelessWidget {
  const MockCamera({
    super.key,
    required this.figure,
    required this.overlay,
    this.arming = const ArmingStatus(ArmingState.waiting),
    this.holdProgress = 0,
    this.highlightLens = 0,
    this.flash,
  });

  final TutorialFigure figure;
  final MockOverlay overlay;

  /// Estado del armado que muestran los avisos ([MockOverlay.arming]).
  final ArmingStatus arming;

  /// Avance del gesto de reintento ([MockOverlay.results]).
  final double holdProgress;

  /// 0..1: resalta la cámara frontal (pulso alrededor del lente).
  final double highlightLens;

  /// Texto grande al centro (p. ej. "3", "¡YA!", "Reintentando…").
  final String? flash;

  static const _screen = Size(360, 740);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: Container(
        width: _screen.width + 20,
        height: _screen.height + 20,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF111316),
          borderRadius: BorderRadius.circular(44),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: SizedBox.fromSize(
            size: _screen,
            // Sin los márgenes del teléfono real: los avisos llevan SafeArea.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              // Es una "captura" escalada del teléfono: el tamaño de letra del
              // sistema no debe deformarla.
              child: MediaQuery.withNoTextScaling(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _RoomPainter()),
                    CustomPaint(painter: _BodyPainter(figure)),
                    CustomPaint(
                      painter: PosePainter(
                        frames: _Fixed(figure.toFrame()),
                        isFront: false,
                      ),
                    ),
                    IgnorePointer(child: _overlay()),
                    if (flash != null) _Flash(text: flash!),
                    _Lens(highlight: highlightLens),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay() {
    switch (overlay) {
      case MockOverlay.arming:
        return Stack(children: [
          ArmingOverlay(
            status: arming,
            stillnessEnabled: true,
            onStartNow: () {},
          ),
        ]);
      case MockOverlay.starting:
        return const SizedBox.shrink();
      case MockOverlay.results:
        return _ResultsMock(progress: holdProgress);
    }
  }
}

/// [PosePainter] pide un `ValueListenable`; aquí el fotograma ya está fijo.
class _Fixed implements ValueListenable<PoseFrame> {
  _Fixed(this.value);

  @override
  final PoseFrame value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Una sala sencilla vista desde el teléfono: pared, piso y un marco de
/// puerta para dar profundidad.
class _RoomPainter extends CustomPainter {
  const _RoomPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final floorY = size.height * 0.80;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, floorY),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5B6475), Color(0xFF7A8496)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, floorY)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, floorY, size.width, size.height - floorY),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6B4F3A), Color(0xFF4A3628)],
        ).createShader(
            Rect.fromLTWH(0, floorY, size.width, size.height - floorY)),
    );
    // Puerta al fondo.
    final door = Paint()
      ..color = const Color(0xFF4B5262)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.70, floorY - size.height * 0.42,
          size.width * 0.22, size.height * 0.42),
      door,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Silueta de la persona (debajo del esqueleto): extremidades redondeadas y
/// cabeza, con ropa oscura.
class _BodyPainter extends CustomPainter {
  _BodyPainter(this.figure);

  final TutorialFigure figure;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(int type) {
      final (x, y) = figure.point(type);
      return Offset(x * size.width, y * size.height);
    }

    final h = figure.height * size.height;
    final limb = Paint()
      ..color = const Color(0xFF263238)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.065;
    final skin = Paint()..color = const Color(0xFFD7A982);

    // Torso como trapecio relleno.
    final torso = Path()
      ..moveTo(
          at(PoseLandmarks.leftShoulder).dx, at(PoseLandmarks.leftShoulder).dy)
      ..lineTo(at(PoseLandmarks.rightShoulder).dx,
          at(PoseLandmarks.rightShoulder).dy)
      ..lineTo(at(PoseLandmarks.rightHip).dx, at(PoseLandmarks.rightHip).dy)
      ..lineTo(at(PoseLandmarks.leftHip).dx, at(PoseLandmarks.leftHip).dy)
      ..close();
    canvas.drawPath(torso, Paint()..color = const Color(0xFF00897B));
    canvas.drawPath(
      torso,
      Paint()
        ..color = const Color(0xFF00897B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.05
        ..strokeJoin = StrokeJoin.round,
    );
    for (final (a, b) in const [
      (PoseLandmarks.leftHip, PoseLandmarks.leftKnee),
      (PoseLandmarks.leftKnee, PoseLandmarks.leftAnkle),
      (PoseLandmarks.rightHip, PoseLandmarks.rightKnee),
      (PoseLandmarks.rightKnee, PoseLandmarks.rightAnkle),
    ]) {
      canvas.drawLine(at(a), at(b), limb);
    }
    final arm = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.045;
    for (final (a, b) in const [
      (PoseLandmarks.leftShoulder, PoseLandmarks.leftElbow),
      (PoseLandmarks.rightShoulder, PoseLandmarks.rightElbow),
    ]) {
      canvas.drawLine(at(a), at(b), arm);
    }
    final forearm = Paint()
      ..color = skin.color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.035;
    for (final (a, b) in const [
      (PoseLandmarks.leftElbow, PoseLandmarks.leftWrist),
      (PoseLandmarks.rightElbow, PoseLandmarks.rightWrist),
    ]) {
      canvas.drawLine(at(a), at(b), forearm);
    }
    // Tenis.
    final shoe = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.04;
    canvas.drawLine(
        at(PoseLandmarks.leftHeel), at(PoseLandmarks.leftFootIndex), shoe);
    canvas.drawLine(
        at(PoseLandmarks.rightHeel), at(PoseLandmarks.rightFootIndex), shoe);
    // Cuello y cabeza.
    final neck =
        (at(PoseLandmarks.leftShoulder) + at(PoseLandmarks.rightShoulder)) / 2;
    final nose = at(0);
    canvas.drawLine(
        neck,
        nose,
        Paint()
          ..color = skin.color
          ..strokeWidth = h * 0.04);
    canvas.drawCircle(nose, h * 0.06, skin);
    canvas.drawArc(
      Rect.fromCircle(center: nose, radius: h * 0.062),
      3.3,
      2.8,
      false,
      Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.03,
    );
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}

/// Lente de la cámara frontal arriba al centro, con un pulso para señalarla.
class _Lens extends StatelessWidget {
  const _Lens({required this.highlight});

  final double highlight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16 + 30 * highlight,
              height: 16 + 30 * highlight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: highlight > 0
                    ? Border.all(
                        color: const Color(0xFF69F0AE)
                            .withValues(alpha: highlight),
                        width: 3)
                    : null,
              ),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            if (highlight > 0.3)
              Opacity(
                opacity: ((highlight - 0.3) / 0.7).clamp(0.0, 1.0),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF69F0AE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Cámara frontal',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Flash extends StatelessWidget {
  const _Flash({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF69F0AE),
          fontSize: 64,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black87, blurRadius: 16)],
        ),
      ),
    );
  }
}

/// Resultado del intento abierto abajo (como el de la evaluación) con el
/// recordatorio del gesto de reintento arriba y su anillo de carga.
class _ResultsMock extends StatelessWidget {
  const _ResultsMock({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF69F0AE);
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.accessibility_new, color: accent, size: 20),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Manos en la cintura para reintentar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (progress > 0)
          Align(
            alignment: const Alignment(0, -0.35),
            child: SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 9,
                backgroundColor: Colors.black45,
                valueColor: const AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F2FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resultado',
                    style: TextStyle(fontSize: 14, color: Colors.black54)),
                SizedBox(height: 4),
                Text('78% de precisión',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87)),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _FakeButton('Salir')),
                    SizedBox(width: 8),
                    Expanded(child: _FakeButton('Reintentar', strong: true)),
                    SizedBox(width: 8),
                    Expanded(child: _FakeButton('Siguiente')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FakeButton extends StatelessWidget {
  const _FakeButton(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFE8DEF8) : null,
        border: strong ? null : Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ),
    );
  }
}
