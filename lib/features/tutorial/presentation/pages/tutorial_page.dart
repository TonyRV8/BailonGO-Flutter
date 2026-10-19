import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../evaluation/engine/start_gesture_detector.dart';
import '../../domain/tutorial_figure.dart';
import '../widgets/mock_camera.dart';
import '../widgets/phone_scene.dart';

/// Tutorial de uso de la evaluación: dónde poner el teléfono, cómo encuadrarse
/// y los gestos para iniciar (brazos arriba) y reintentar (manos en la
/// cintura).
///
/// Las escenas de cámara simulan la pantalla REAL de la evaluación: mismo
/// esqueleto y mismos avisos, para que al evaluar nada sea sorpresa. Avanza
/// solo; también se puede ir y volver con los botones.
///
/// Devuelve `true` si el usuario termina o lo salta (y quiere seguir), `null`
/// si sale con el gesto atrás.
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key, this.beforeEvaluation = false});

  /// Se muestra justo antes de evaluar: el botón final dice "¡A bailar!".
  final bool beforeEvaluation;

  static Route<bool> route({bool beforeEvaluation = false}) =>
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => TutorialPage(beforeEvaluation: beforeEvaluation),
      );

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

/// Una escena: textos, duración y cómo se dibuja en el segundo `s`.
class _Scene {
  const _Scene(this.title, this.caption, this.seconds, this.build);

  final String title;
  final String caption;
  final double seconds;
  final Widget Function(double s) build;
}

class _TutorialPageState extends State<TutorialPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  int _index = 0;

  late final List<_Scene> _scenes = [
    _Scene(
      'Pon el celular a la altura que quieras',
      'En una mesa, un tripié o una repisa: lo importante es que la cámara '
          'te vea completo.',
      6,
      _placeScene,
    ),
    _Scene(
      'Pero que quede fijo',
      'Si lo sostienes con la mano se mueve y la evaluación falla. Apóyalo y '
          'no lo toques.',
      5,
      _steadyScene,
    ),
    _Scene(
      'Usa la cámara frontal y aléjate',
      'Tienes que verte de pies a cabeza en la pantalla (a ~1.4 m). La app '
          'te avisa si falta algo.',
      7,
      _frameScene,
    ),
    _Scene(
      'Levanta los brazos para empezar',
      'Mantenlos arriba hasta que se llene el círculo y arranca la cuenta '
          'regresiva.',
      6.5,
      _startScene,
    ),
    _Scene(
      'Manos en la cintura para reintentar',
      'Al terminar, ponte en jarras para repetir el paso sin volver al '
          'teléfono.',
      6.5,
      _retryScene,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this)
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        // Avanza solo; la última escena se repite hasta que el usuario sigue.
        _go(_isLast ? _index : _index + 1);
      });
    _go(0);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _go(int index) {
    setState(() => _index = index);
    _clock
      ..duration =
          Duration(milliseconds: (_scenes[index].seconds * 1000).round())
      ..forward(from: 0);
  }

  bool get _isLast => _index == _scenes.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop(true);
    } else {
      _go(_index + 1);
    }
  }

  // ------------------------------------------------------------- escenas
  static double _seg(double s, double from, double to) =>
      ((s - from) / (to - from)).clamp(0.0, 1.0);

  static double _ease(double t) => Curves.easeInOut.transform(t);

  /// 1. El teléfono pasa por mesa, tripié y repisa: todas valen.
  Widget _placeScene(double s) {
    const heights = [0.80, 1.18, 1.66];
    final i = math.min(2, s ~/ 2);
    final local = s - i * 2;
    final from = heights[math.max(0, i - 1)];
    final h = lerpDouble(from, heights[i], _ease(_seg(local, 0, 0.6)))!;
    return _padded(PhoneScene(
      phoneHeight: h,
      place: i,
      mark: _seg(local, 0.6, 1.0),
    ));
  }

  /// 2. En la mano tiembla (✗); apoyado en el tripié queda fijo (✓).
  Widget _steadyScene(double s) {
    final toTripod = _ease(_seg(s, 3.0, 3.8));
    return _padded(PhoneScene(
      phoneHeight: lerpDouble(1.25, 1.18, toTripod)!,
      place: toTripod < 1 ? -1 : 1,
      shake: 1 - toTripod,
      ok: toTripod >= 1,
      mark: toTripod < 1 ? _seg(s, 0.4, 0.8) : _seg(s, 3.9, 4.3),
    ));
  }

  static const _near = TutorialFigure(
    centerX: 0.5,
    top: 0.12,
    height: 1.25,
    arms: {TutorialArms.down: 1},
  );
  static const _far = TutorialFigure(
    centerX: 0.5,
    top: 0.27,
    height: 0.58,
    arms: {TutorialArms.down: 1},
  );

  static TutorialFigure _withArms(
          TutorialFigure f, TutorialArms from, TutorialArms to, double t) =>
      TutorialFigure(
        centerX: f.centerX,
        top: f.top,
        height: f.height,
        arms: from == to ? {to: 1} : {from: 1 - t, to: t},
      );

  /// 3. Muy cerca (le faltan las piernas) → se aleja → encuadrado.
  Widget _frameScene(double s) {
    final back = _ease(_seg(s, 2.2, 4.2));
    final lens = s < 2.0 ? 1.0 : 1 - _seg(s, 2.0, 2.4);
    return MockCamera(
      figure: TutorialFigure.lerp(_near, _far, back),
      // Primero se señala la cámara frontal; luego aparecen los avisos (si
      // no, la etiqueta queda debajo del aviso).
      overlay: s < 2.2 ? MockOverlay.starting : MockOverlay.arming,
      arming:
          ArmingStatus(s < 4.4 ? ArmingState.outOfFrame : ArmingState.waiting),
      highlightLens: lens,
    );
  }

  /// 4. Brazos arriba → se llena el anillo → cuenta regresiva.
  Widget _startScene(double s) {
    final up = _ease(_seg(s, 1.0, 1.6));
    final down = _ease(_seg(s, 3.8, 4.4));
    final arms = down > 0
        ? _withArms(_far, TutorialArms.up, TutorialArms.down, down)
        : _withArms(_far, TutorialArms.down, TutorialArms.up, up);
    if (s >= 3.6) {
      const labels = ['3', '2', '1', '¡YA!'];
      final k = math.min(3, ((s - 3.6) / 0.7).floor());
      return MockCamera(
        figure: arms,
        overlay: MockOverlay.starting,
        flash: labels[k],
      );
    }
    final hold = _seg(s, 1.6, 3.6);
    return MockCamera(
      figure: arms,
      overlay: MockOverlay.arming,
      arming: hold > 0
          ? ArmingStatus(ArmingState.raisingArms, progress: hold)
          : const ArmingStatus(ArmingState.waiting),
    );
  }

  /// 5. Resultado abierto → manos en la cintura → se reintenta.
  Widget _retryScene(double s) {
    final toHips = _ease(_seg(s, 1.2, 1.8));
    final release = _ease(_seg(s, 5.0, 5.6));
    final figure = release > 0
        ? _withArms(_far, TutorialArms.hips, TutorialArms.down, release)
        : _withArms(_far, TutorialArms.down, TutorialArms.hips, toHips);
    return MockCamera(
      figure: figure,
      overlay: MockOverlay.results,
      holdProgress: s < 3.8 ? _seg(s, 1.8, 3.8) : 0,
      flash: s >= 3.8 && s < 5.4 ? '¡Otra\nvez!' : null,
    );
  }

  Widget _padded(Widget child) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      );

  // ----------------------------------------------------------------- UI
  void _back() {
    if (_index > 0) _go(_index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scene = _scenes[_index];
    final s = _clock.value * scene.seconds;
    // Con letra muy grande del sistema el texto se comía la animación y
    // empujaba los botones fuera de la pantalla: se limita en esta página.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Scaffold(
        backgroundColor: const Color(0xFF101418),
        // Botones siempre visibles, fijos abajo.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _index > 0 ? _back : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white24,
                  ),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Atrás'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _go(0),
                  tooltip: 'Ver de nuevo',
                  color: Colors.white,
                  icon: const Icon(Icons.replay),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    // Texto encogible: en pantallas angostas no desborda.
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_isLast
                                ? (widget.beforeEvaluation
                                    ? '¡A bailar!'
                                    : 'Entendido')
                                : 'Siguiente'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(_isLast ? Icons.check : Icons.chevron_right,
                            size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barras de avance (una por escena) y salir.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < _scenes.length; i++) ...[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: i < _index
                                ? 1
                                : i == _index
                                    ? _clock.value
                                    : 0,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFF69F0AE)),
                          ),
                        ),
                      ),
                      if (i < _scenes.length - 1) const SizedBox(width: 4),
                    ],
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      tooltip: 'Saltar tutorial',
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Textos de la escena, bien separados de las barras.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paso ${_index + 1} de ${_scenes.length}',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: const Color(0xFF69F0AE)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scene.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scene.caption,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),
              ),
              // La animación ocupa todo lo que queda. Tocar a la derecha
              // avanza y a la izquierda retrocede (como las historias).
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      if (d.localPosition.dx < box.maxWidth / 3) {
                        _back();
                      } else if (!_isLast) {
                        // En la última no sale: para eso está el botón.
                        _go(_index + 1);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: scene.build(s)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
