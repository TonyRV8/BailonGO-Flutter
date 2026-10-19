import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/step_cues.dart';

/// Flechas guía sobre la cámara mientras el usuario baila: el "filtro" del
/// paso (RF-08). Lee la pista fija de [cuesFor] y el reloj de la captura, así
/// que va sincronizada con el video guía y con la música sin depender de lo
/// que detecte la pose.
///
/// Se dibuja encima de la preview y no toca eventos: es puramente visual.
class CueOverlay extends StatefulWidget {
  const CueOverlay({
    super.key,
    required this.clock,
    required this.cues,
    this.mirrored = true,
  });

  /// Reloj de la captura (arranca en el "¡YA!").
  final Stopwatch clock;

  final List<StepCue> cues;

  /// La preview va en espejo (cámara frontal). Con la trasera, izquierda y
  /// derecha se invierten para que la flecha señale el lado real.
  final bool mirrored;

  @override
  State<CueOverlay> createState() => _CueOverlayState();
}

class _CueOverlayState extends State<CueOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Milisegundos de captura. En un ValueNotifier para que el tick a 60 fps
  /// repinte solo la flecha y no toda la pantalla de evaluación.
  final ValueNotifier<int> _elapsed = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _elapsed.value = widget.clock.elapsedMilliseconds;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  /// Señal activa en [ms]: de "Mostrar" hasta su fin. Si dos se solapan gana
  /// la que empieza más tarde (la siguiente figura manda sobre la que ya se
  /// está acabando).
  StepCue? _activeAt(int ms) {
    StepCue? found;
    for (final cue in widget.cues) {
      if (ms >= cue.showMs && ms < cue.endMs) found = cue;
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<int>(
          valueListenable: _elapsed,
          builder: (context, ms, _) {
            final cue = _activeAt(ms);
            if (cue == null) return const SizedBox.expand();
            return _CueArrow(
              // Con cámara trasera se voltea la flecha; el texto no, porque
              // DER/IZQ hablan del cuerpo.
              dir: widget.mirrored ? cue.dir : _flip(cue.dir),
              label: cue.label,
              // 0 al aparecer, 1 en el tiempo marcado, >1 mientras dura.
              phase: (ms - cue.tMs + kCueLeadMs) / kCueLeadMs,
              fade: _fade(ms, cue),
            );
          },
        ),
      ),
    );
  }

  /// Entra en los primeros 150 ms y se apaga en los últimos 150 ms.
  double _fade(int ms, StepCue cue) {
    final since = ms - cue.showMs;
    final toEnd = cue.endMs - ms;
    return math.min(
      (since / 150).clamp(0.0, 1.0),
      (toEnd / 150).clamp(0.0, 1.0),
    );
  }

  static CueDir _flip(CueDir d) => switch (d) {
        CueDir.left => CueDir.right,
        CueDir.right => CueDir.left,
        CueDir.upLeft => CueDir.upRight,
        CueDir.upRight => CueDir.upLeft,
        CueDir.downLeft => CueDir.downRight,
        CueDir.downRight => CueDir.downLeft,
        CueDir.turnLeft => CueDir.turnRight,
        CueDir.turnRight => CueDir.turnLeft,
        _ => d,
      };
}

/// Una flecha con su etiqueta. Las laterales y diagonales van en el borde al
/// que hay que moverse; adelante/atrás arriba al centro, lejos de los pies, y
/// los giros al centro. La palabra va siempre: la flecha sola no distingue
/// ADEL DER de PATADA ADELANTE.
class _CueArrow extends StatelessWidget {
  const _CueArrow({
    required this.dir,
    required this.label,
    required this.phase,
    required this.fade,
  });

  final CueDir dir;
  final String label;

  /// 0 al aparecer, 1 justo en el tiempo de la señal.
  final double phase;
  final double fade;

  @override
  Widget build(BuildContext context) {
    const top = Alignment(0, -0.62);
    final (icon, align) = switch (dir) {
      CueDir.forward => (Icons.arrow_upward, top),
      CueDir.back => (Icons.arrow_downward, top),
      CueDir.right => (Icons.arrow_forward, Alignment.centerRight),
      CueDir.left => (Icons.arrow_back, Alignment.centerLeft),
      CueDir.upRight => (Icons.north_east, const Alignment(1, -0.45)),
      CueDir.upLeft => (Icons.north_west, const Alignment(-1, -0.45)),
      CueDir.downRight => (Icons.south_east, const Alignment(1, 0.2)),
      CueDir.downLeft => (Icons.south_west, const Alignment(-1, 0.2)),
      CueDir.turnRight => (Icons.rotate_right, Alignment.center),
      CueDir.turnLeft => (Icons.rotate_left, Alignment.center),
      CueDir.close => (Icons.circle, top),
    };

    // Antes del tiempo marcado la flecha se desliza hacia su borde; al llegar
    // da un golpe de escala, que es lo que marca el tiempo musical.
    final slide = (1 - phase.clamp(0.0, 1.0)) * 48;
    final pulse = phase < 1
        ? 1.0
        : 1 + 0.18 * math.max(0, 1 - (phase - 1) * 4) * (fade > 0 ? 1 : 0);
    final offset = switch (dir) {
      CueDir.left => Offset(slide, 0),
      CueDir.right => Offset(-slide, 0),
      CueDir.upLeft => Offset(slide, slide) * 0.7,
      CueDir.upRight => Offset(-slide, slide) * 0.7,
      CueDir.downLeft => Offset(slide, -slide) * 0.7,
      CueDir.downRight => Offset(-slide, -slide) * 0.7,
      CueDir.forward => Offset(0, slide),
      CueDir.back => Offset(0, -slide),
      _ => Offset.zero,
    };

    // Tamaño relativo a la pantalla: la flecha tiene que leerse a varios
    // metros del teléfono, que es desde donde se baila. Con tope para que en
    // una tablet no ocupe media pantalla.
    final shortest = MediaQuery.of(context).size.shortestSide;
    final size = (shortest * 0.42).clamp(120.0, 200.0);

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Transform.translate(
          offset: offset,
          child: Transform.scale(
            scale: pulse,
            child: Opacity(
              opacity: fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    // El punto de CIERRA lleno a tamaño completo tapa demasiado.
                    size: dir == CueDir.close ? size * 0.45 : size,
                    color: Colors.white,
                    shadows: const [
                      Shadow(blurRadius: 22, color: Colors.black87),
                      Shadow(blurRadius: 44, color: Colors.black54),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black
                          .withValues(alpha: lerpDouble(0, 0.55, fade)!),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        fontSize: size * 0.13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
