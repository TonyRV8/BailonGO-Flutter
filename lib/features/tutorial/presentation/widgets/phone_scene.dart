import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Escena lateral: el teléfono a la izquierda y la persona a la derecha, con el
/// cono de lo que ve la cámara frontal. Explica que la altura da igual (mesa,
/// tripié o repisa) mientras el teléfono quede FIJO y la persona entre
/// completa.
///
/// Medidas en metros; el pintor las escala al lienzo.
class PhoneScene extends StatelessWidget {
  const PhoneScene({
    super.key,
    required this.phoneHeight,
    required this.place,
    this.shake = 0,
    this.ok = true,
    this.mark = 1,
  });

  /// Altura del teléfono sobre el piso (m).
  final double phoneHeight;

  /// Soporte resaltado: 0 mesa, 1 tripié, 2 repisa, -1 en la mano.
  final int place;

  /// Cuánto tiembla el teléfono (0 quieto … 1 en la mano).
  final double shake;

  /// El encuadre es válido (cono verde y ✓) o no (cono rojo y ✗).
  final bool ok;

  /// 0..1: aparición de la marca ✓/✗.
  final double mark;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _SceneGeom.width / _SceneGeom.height,
      child: CustomPaint(
        painter: _ScenePainter(
          phoneHeight: phoneHeight,
          place: place,
          shake: shake,
          ok: ok,
          mark: mark,
        ),
      ),
    );
  }
}

/// Mundo de la escena en metros.
abstract final class _SceneGeom {
  static const width = 3.4;
  static const height = 2.2;
  static const wallX = 0.15;
  static const phoneX = 0.62;
  static const personX = 2.75;
  static const personH = 1.65;
  static const tableH = 0.74;
  static const tripodH = 1.10;
  static const shelfH = 1.60;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.phoneHeight,
    required this.place,
    required this.shake,
    required this.ok,
    required this.mark,
  });

  final double phoneHeight;
  final int place;
  final double shake;
  final bool ok;
  final double mark;

  static const _good = Color(0xFF69F0AE);
  static const _bad = Color(0xFFFF6E6E);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _SceneGeom.width;
    final floorY = size.height - 0.12 * k;
    Offset p(double x, double y) => Offset(x * k, floorY - y * k);

    // Piso y pared.
    canvas.drawRect(
      Rect.fromLTRB(0, floorY, size.width, size.height),
      Paint()..color = const Color(0xFF4A3628),
    );
    canvas.drawLine(
      p(_SceneGeom.wallX, 0),
      p(_SceneGeom.wallX, _SceneGeom.height),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 3,
    );

    final propPaint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // El soporte en uso resalta; los otros apenas se insinúan.
    Color prop(int i) =>
        i == place ? Colors.white : Colors.white.withValues(alpha: 0.08);

    // Mesa.
    propPaint.color = prop(0);
    canvas.drawLine(p(0.35, _SceneGeom.tableH - 0.04),
        p(0.95, _SceneGeom.tableH - 0.04), propPaint..strokeWidth = 6);
    propPaint.strokeWidth = 4;
    canvas.drawLine(p(0.42, _SceneGeom.tableH - 0.04), p(0.42, 0), propPaint);
    canvas.drawLine(p(0.88, _SceneGeom.tableH - 0.04), p(0.88, 0), propPaint);
    // Tripié.
    propPaint.color = prop(1);
    final top = p(_SceneGeom.phoneX + 0.02, _SceneGeom.tripodH - 0.08);
    canvas.drawLine(top, p(_SceneGeom.phoneX - 0.22, 0), propPaint);
    canvas.drawLine(top, p(_SceneGeom.phoneX + 0.26, 0), propPaint);
    canvas.drawLine(top, p(_SceneGeom.phoneX + 0.02, 0), propPaint);
    // Repisa en la pared.
    propPaint.color = prop(2);
    canvas.drawLine(p(_SceneGeom.wallX, _SceneGeom.shelfH - 0.05),
        p(0.85, _SceneGeom.shelfH - 0.05), propPaint..strokeWidth = 6);

    // Persona de perfil mirando al teléfono.
    _person(canvas, p, k);

    // Teléfono (tiembla si está en la mano) apuntando al centro del cuerpo.
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final jitter = Offset(math.sin(t * 23) * 0.025 + math.sin(t * 7) * 0.02,
            math.cos(t * 19) * 0.02) *
        shake;
    final phone = p(_SceneGeom.phoneX, phoneHeight) + jitter * k;
    final aim = p(_SceneGeom.personX, _SceneGeom.personH / 2);
    final angle = math.atan2(aim.dy - phone.dy, aim.dx - phone.dx) +
        shake * math.sin(t * 11) * 0.18;

    // Cono de visión de la cámara frontal: debe abarcar de la cabeza a los
    // pies.
    final color = ok ? _good : _bad;
    final reach = (_SceneGeom.personX - _SceneGeom.phoneX + 0.25) * k;
    const half = 0.62; // medio ángulo de visión (rad)
    final cone = Path()
      ..moveTo(phone.dx, phone.dy)
      ..lineTo(phone.dx + math.cos(angle - half) * reach,
          phone.dy + math.sin(angle - half) * reach)
      ..lineTo(phone.dx + math.cos(angle + half) * reach,
          phone.dy + math.sin(angle + half) * reach)
      ..close();
    // El cono no atraviesa el piso.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, floorY));
    canvas.drawPath(cone, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      cone,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Mano sosteniendo el teléfono.
    if (place == -1) {
      canvas.drawLine(
        phone + Offset(-0.05 * k, 0.12 * k),
        phone + Offset(-0.32 * k, 0.45 * k),
        Paint()
          ..color = const Color(0xFFD7A982)
          ..strokeWidth = 0.07 * k
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.save();
    canvas.translate(phone.dx, phone.dy);
    canvas.rotate(angle + math.pi / 2);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 0.20 * k, height: 0.045 * k),
      Radius.circular(0.012 * k),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF111316));
    canvas.drawRRect(
      body,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Marca ✓ / ✗ sobre la persona.
    if (mark > 0) {
      final c = p(_SceneGeom.personX, _SceneGeom.personH + 0.32);
      final r = 0.16 * k * Curves.easeOutBack.transform(mark.clamp(0, 1));
      canvas.drawCircle(c, r, Paint()..color = color);
      final s = Paint()
        ..color = Colors.black
        ..strokeWidth = r * 0.22
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (ok) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.45, c.dy)
            ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
            ..lineTo(c.dx + r * 0.5, c.dy - r * 0.35),
          s,
        );
      } else {
        canvas.drawLine(
            c + Offset(-r * 0.4, -r * 0.4), c + Offset(r * 0.4, r * 0.4), s);
        canvas.drawLine(
            c + Offset(r * 0.4, -r * 0.4), c + Offset(-r * 0.4, r * 0.4), s);
      }
    }
  }

  void _person(Canvas canvas, Offset Function(double, double) p, double k) {
    const x = _SceneGeom.personX;
    const h = _SceneGeom.personH;
    final skin = Paint()..color = const Color(0xFFD7A982);
    final shirt = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeWidth = 0.16 * k
      ..strokeCap = StrokeCap.round;
    final legs = Paint()
      ..color = const Color(0xFF263238)
      ..strokeWidth = 0.11 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(x, h * 0.48), p(x - 0.04, 0.06), legs);
    canvas.drawLine(p(x, h * 0.48), p(x + 0.05, 0.06), legs);
    canvas.drawLine(
        p(x - 0.10, 0.03),
        p(x + 0.12, 0.03),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 0.06 * k
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(p(x, h * 0.52), p(x, h * 0.80), shirt);
    canvas.drawLine(
        p(x, h * 0.78),
        p(x - 0.03, h * 0.50),
        Paint()
          ..color = skin.color
          ..strokeWidth = 0.06 * k
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(p(x - 0.01, h * 0.93), 0.11 * k, skin);
  }

  // El teléfono tiembla con el reloj: se repinta en cada fotograma.
  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}
