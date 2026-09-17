import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/config/app_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../catalog/domain/entities/dance_step.dart';
import '../../../catalog/domain/step_weights.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../pose/data/camera_input.dart';
import '../../../pose/domain/entities/pose_frame.dart';
import '../../../pose/presentation/providers/pose_providers.dart';
import '../../../pose/presentation/widgets/pose_painter.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/evaluation_feedback.dart';
import '../../engine/dtw_comparator.dart';
import '../../engine/step_params.dart';
import '../../engine/dtw_result.dart';
import '../../engine/feature_extractor.dart';
import '../../engine/frame_resampler.dart';
import '../../engine/retry_gesture_detector.dart';
import '../../engine/start_gesture_detector.dart';
import '../providers/evaluation_providers.dart';
import '../widgets/arming_overlay.dart';
import '../widgets/results_sheet.dart';

// La referencia se extrae con isMirrored=false; la captura en vivo se procesa
// igual (raw NV21, sin flip) para que coincidan. Si la lateralidad sale
// invertida en el dispositivo, el usuario activa "Corregir lateralidad" en
// Configuración (users.settings.mirrorCapture).

enum _Phase {
  preparing,
  noVideo,

  /// Cámara viva esperando la señal del usuario, sin reloj corriendo
  /// (RF-08.1). Es la primera fase visible: al entrar al paso no hay ningún
  /// botón intermedio que pulsar.
  arming,

  countdown,
  capturing,
  computing,

  /// Modal de resultados abierto. La cámara sigue viva por debajo para poder
  /// reintentar con las manos en la cintura (RF-11).
  results,

  error,
  denied,
}

/// Flujo de evaluación end-to-end (RF-08..RF-11).
class EvaluationPage extends ConsumerStatefulWidget {
  const EvaluationPage({super.key, required this.stepId});

  final String stepId;

  @override
  ConsumerState<EvaluationPage> createState() => _EvaluationPageState();
}

class _EvaluationPageState extends ConsumerState<EvaluationPage>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  CameraDescription? _camera;

  _Phase _phase = _Phase.preparing;
  String? _error;

  DanceStep? _step;
  List<List<double>> _refFrames = const [];

  bool _busy = false;
  final ValueNotifier<PoseFrame> _frames = ValueNotifier(PoseFrame.empty);
  final List<List<double>> _userFrames = [];

  /// Instante (ms desde el ¡YA!) en que llegó la imagen de cada vector de
  /// [_userFrames]. El detector no siempre llega a 30 fps; con estos tiempos
  /// la captura se lleva a la rejilla de 33 ms de la referencia antes de
  /// comparar (ver [FrameResampler]).
  final List<int> _userTimesMs = [];
  final Stopwatch _captureClock = Stopwatch();

  /// Durante el armado no hace falta inferir a 30 fps: el detector trabaja por
  /// tiempo, no por fotogramas. Procesar 1 de cada 2 baja a la mitad el consumo
  /// en una espera que puede durar minutos.
  int _armingSkip = 0;

  int _countdown = AppConstants.countdownSeconds;
  bool _showGo = false;

  // Armado previo al conteo (RF-08.1..08.5).
  final StartGestureDetector _gesture = StartGestureDetector(
    stillnessHold: const Duration(seconds: AppConstants.stillnessSeconds),
  );
  ArmingStatus _arming = const ArmingStatus(ArmingState.noBody);

  // Reintento por gesto desde el modal de resultados (RF-11).
  final RetryGestureDetector _retryGesture = RetryGestureDetector();
  bool _resultsOpen = false;
  Timer? _countdownTimer;
  Timer? _goTimer;
  Timer? _captureTimer;
  double _progress = 0;

  /// Invalida un conteo en curso si se reinicia o se sale antes de que la
  /// música termine de arrancar.
  int _countdownToken = 0;

  // Conteo audible (RF-08): un pitido por numero y uno largo al arrancar.
  static final _tickSound = AssetSource('sounds/tick.wav');
  static final _goSound = AssetSource('sounds/go.wav');
  final AudioPlayer _tickPlayer = AudioPlayer(playerId: 'countdown_tick');
  final AudioPlayer _goPlayer = AudioPlayer(playerId: 'countdown_go');

  // Musica del intento: suena desde el ¡YA! hasta el final de la captura, NO
  // durante el conteo. Las 9 tomas de la profesora empiezan en el mismo punto
  // de musica.mp3 (0.09 s), asi que sirve una sola pista: `musica_intento.m4a`
  // = el tema desde ese punto. Queda alineada con la referencia: el segundo 0
  // de la pista es el fotograma 0 de la toma (implementar_pasos.txt §7-quater).
  static final _attemptMusic = AssetSource('sounds/musica_intento.m4a');
  final AudioPlayer _musicPlayer = AudioPlayer(playerId: 'step_music');

  /// Solo los pasos reales van sobre ese tema; los de prueba usan otro video.
  bool get _hasMusic => kRealStepIds.contains(widget.stepId);

  // Pulso de entrada de cada numero del conteo.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initAudio();
    _init();
  }

  Future<void> _initAudio() async {
    try {
      // Sin robar el foco de audio: con el foco por defecto (gain) el pitido
      // del conteo pausaba el video guía y la música que el usuario tuviera
      // sonando, y ninguno se reanudaba solo.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
      for (final e in {_tickPlayer: _tickSound, _goPlayer: _goSound}.entries) {
        await e.key.setReleaseMode(ReleaseMode.stop);
        await e.key.setVolume(1);
        // Precarga para que el primer pitido no llegue tarde.
        await e.key.setSource(e.value);
      }
      await _musicPlayer.setReleaseMode(ReleaseMode.stop);
      await _musicPlayer.setVolume(1);
      if (_hasMusic) await _musicPlayer.setSource(_attemptMusic);
    } catch (_) {
      // Sin audio disponible: el conteo sigue siendo visual y la captura mide
      // igual, solo que sin musica de apoyo.
    }
  }

  Future<void> _init() async {
    final granted = await Permission.camera.request();
    if (!granted.isGranted) {
      if (mounted) setState(() => _phase = _Phase.denied);
      return;
    }
    try {
      // Paso + referencia (se asegura que el catálogo esté cargado).
      final steps = await ref.read(catalogProvider.future);
      final step = steps.firstWhere(
        (s) => s.id == widget.stepId,
        orElse: () => throw StateError('Paso no encontrado'),
      );
      _step = step;

      await _initCamera();

      final refFrames =
          await ref.read(referenceRepositoryProvider).framesFor(step);
      _refFrames = refFrames;

      if (!mounted) return;
      if (refFrames.isEmpty) {
        setState(() => _phase = _Phase.noVideo);
      } else {
        // Sin paso intermedio: la cámara ya está lista, se arma directamente.
        _startArming();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _camera = front;
    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await ref.read(poseLandmarkerProvider).initialize();
    await controller.startImageStream(_onImage);
  }

  Future<void> _onImage(CameraImage image) async {
    if (_busy || !mounted) return;
    final camera = _camera;
    if (camera == null) return;
    // Ni la espera ni el modal de resultados necesitan inferencia a 30 fps:
    // ambos detectores trabajan por tiempo, no por fotogramas.
    if ((_phase == _Phase.arming || _phase == _Phase.results) &&
        (_armingSkip++ & 1) == 1) {
      return;
    }
    _busy = true;
    // Se toma al RECIBIR la imagen, no al terminar la inferencia: la latencia
    // del modelo es casi constante y no debe contarse como retraso del alumno.
    final receivedMs = _captureClock.elapsedMilliseconds;
    try {
      final data = cameraFrameFromImage(
        image: image,
        camera: camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      if (data == null) return;
      final frame = await ref.read(poseLandmarkerProvider).detect(
            nv21: data.nv21,
            width: data.width,
            height: data.height,
            rotationDegrees: data.rotationDegrees,
          );
      if (_phase == _Phase.capturing) {
        // La imagen llega girada; MediaPipe normaliza sobre la imagen ya
        // vertical, así que alto y ancho se intercambian a 90/270 grados.
        final upright = data.rotationDegrees % 180 == 0;
        final aspect = upright
            ? data.height / data.width
            : data.width / data.height;
        final v = FeatureExtractor.extractFeatures(
          frame.landmarks,
          isMirrored: ref.read(currentSettingsProvider).mirrorCapture,
          aspectRatio: aspect,
        );
        if (v != null) {
          _userFrames.add(v);
          _userTimesMs.add(receivedMs);
        }
      } else if (_phase == _Phase.arming) {
        _updateArming(frame);
      } else if (_phase == _Phase.results) {
        _updateRetryGesture(frame);
      }
      if (mounted) _frames.value = frame;
    } catch (_) {
      // Fotograma descartado.
    } finally {
      _busy = false;
    }
  }

  /// Entra en espera activa: el conteo no arranca hasta que el usuario dé la
  /// señal (brazos arriba o quietud) o pulse "Iniciar ahora".
  void _startArming() {
    _countdownToken++;
    _countdownTimer?.cancel();
    _goTimer?.cancel();
    _stopStepMusic();
    _gesture
      ..stillnessEnabled = ref.read(currentSettingsProvider).autoStartOnStill
      ..start();
    setState(() {
      _showGo = false;
      _arming = const ArmingStatus(ArmingState.noBody);
      _phase = _Phase.arming;
    });
  }

  /// Evalúa un fotograma durante el armado. Solo se llama a `setState` cuando
  /// el estado visible cambia: el repintado a 30 fps ya lo hace `_onImage`.
  void _updateArming(PoseFrame frame) {
    final status = _gesture.update(frame);
    if (status.isTriggered) {
      _gesture.reset();
      _startCountdown();
      return;
    }
    final changed = status.state != _arming.state ||
        (status.progress - _arming.progress).abs() > 0.02;
    if (changed && mounted) setState(() => _arming = status);
  }

  /// Manos en la cintura sobre el resultado = reintentar sin acercarse al
  /// teléfono. Cierra el modal con la misma acción que el botón "Reintentar".
  void _updateRetryGesture(PoseFrame frame) {
    if (!_resultsOpen) return;
    if (!_retryGesture.update(frame)) return;
    _resultsOpen = false;
    HapticFeedback.mediumImpact();
    // El modal es la ruta superior: se cierra devolviendo la acción de
    // reintento, igual que si se hubiera pulsado el botón.
    Navigator.of(context).pop(ResultsAction.retry);
  }

  Future<void> _startCountdown() async {
    final token = ++_countdownToken;
    _countdownTimer?.cancel();
    _goTimer?.cancel();
    setState(() {
      _countdown = AppConstants.countdownSeconds;
      _showGo = false;
      _phase = _Phase.countdown;
    });
    // La música se deja cargada y en el segundo 0 durante el conteo, en
    // silencio: así en el ¡YA! solo hay que darle play y arranca sin retraso.
    _prepareStepMusic();

    _beat(_tickPlayer, _tickSound, HapticFeedback.mediumImpact);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || token != _countdownToken) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _go();
      } else {
        setState(() => _countdown--);
        _beat(_tickPlayer, _tickSound, HapticFeedback.mediumImpact);
      }
    });
  }

  /// Marca visual + sonora de cada numero del conteo.
  void _beat(
    AudioPlayer player,
    AssetSource sound,
    Future<void> Function() haptic, {
    bool audible = true,
  }) {
    _pulse.forward(from: 0);
    haptic();
    if (audible) _play(player, sound);
  }

  Future<void> _play(AudioPlayer player, AssetSource sound) async {
    try {
      await player.stop();
      await player.play(sound);
    } catch (_) {
      // El conteo no depende del audio.
    }
  }

  /// "YA": arranca la música y la captura a la vez. Con música no suena el
  /// pitido largo: se pisaría con el primer tiempo del tema.
  Future<void> _go() async {
    final token = _countdownToken;
    final withMusic = await _startStepMusic();
    if (!mounted || token != _countdownToken || _phase != _Phase.countdown) {
      return;
    }
    _beat(_goPlayer, _goSound, HapticFeedback.heavyImpact, audible: !withMusic);
    setState(() => _showGo = true);
    _startCapture();
    _goTimer?.cancel();
    _goTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showGo = false);
    });
  }

  int get _captureDurationMs =>
      (_refFrames.length * FrameResampler.stepMs).clamp(1000, 60000).toInt();

  void _startCapture() {
    _userFrames.clear();
    _userTimesMs.clear();
    _captureClock
      ..reset()
      ..start();
    // Captura sincronizada con la duración real del video guía (RN-07):
    // la referencia se muestrea cada 33 ms (~30 fps).
    final durationMs = _captureDurationMs;
    final start = DateTime.now();
    setState(() {
      _phase = _Phase.capturing;
      _progress = 0;
    });
    // Progreso + fin sincronizado con la duración del video guía (RN-07).
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final p = (elapsed / durationMs).clamp(0.0, 1.0);
      setState(() => _progress = p);
      if (elapsed >= durationMs) {
        t.cancel();
        _finishCapture();
      }
    });
  }

  /// Detiene lo que sonara y deja la pista cargada al principio.
  Future<void> _prepareStepMusic() async {
    if (!_hasMusic) return;
    try {
      await _musicPlayer.stop();
      await _musicPlayer.setSource(_attemptMusic);
    } catch (_) {
      // Sin música: la captura no depende de ella.
    }
  }

  /// Arranca la música desde el principio. Devuelve `false` si el paso no
  /// tiene música o no se pudo reproducir (la captura sigue igual).
  Future<bool> _startStepMusic() async {
    if (!_hasMusic) return false;
    try {
      await _musicPlayer.seek(Duration.zero);
      await _musicPlayer.resume();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopStepMusic() async {
    try {
      await _musicPlayer.stop();
    } catch (_) {
      // Nada que parar.
    }
  }

  Future<void> _finishCapture() async {
    _captureClock.stop();
    setState(() => _phase = _Phase.computing);
    await _stopStepMusic();
    final user = FrameResampler.toGrid(
      _userFrames,
      _userTimesMs,
      durationMs: _captureDurationMs,
    );
    final result = DtwComparator.compare(
      user,
      _refFrames,
      // Pesos del código para los pasos reales: el documento de Firestore
      // puede ser de una siembra anterior (22 features, brazos a 0).
      weights: kStepWeights[widget.stepId] ?? _step?.weights,
      params: paramsFor(widget.stepId),
    );

    // Guardar intento (RN-04: la mejor marca se deriva del máximo en HISTORY).
    final account = ref.read(currentUserProvider);
    if (account.isNotEmpty) {
      try {
        await ref.read(attemptRepositoryProvider).save(
              uid: account.uid,
              pasoId: widget.stepId,
              result: result,
            );
        // Refresca la ficha del paso, el catálogo y el progreso del perfil.
        ref.invalidate(bestScoreProvider(widget.stepId));
        ref.invalidate(userBestScoresProvider);
      } catch (_) {
        // Sin red: el intento se mostrará igual; sync queda para Fase 7.
      }
    }

    if (mounted) _showResults(result);
  }

  Future<void> _showResults(DtwResult result) async {
    final nextId = _nextStepId();
    _retryGesture.start();
    _resultsOpen = true;
    setState(() => _phase = _Phase.results);

    final action = await showModalBottomSheet<ResultsAction>(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      // La cámara sigue visible y viva por debajo del modal.
      barrierColor: Colors.transparent,
      builder: (_) => ResultsSheet(
        result: result,
        feedback: buildFeedback(result),
        hasNext: nextId != null,
        canGestureRetry: true,
      ),
    );

    _resultsOpen = false;
    _retryGesture.reset();
    if (!mounted) return;
    if (action == ResultsAction.retry) {
      // La cámara sigue activa y la referencia en memoria, pero el usuario está
      // lejos del teléfono: vuelve al armado para que se recoloque sin prisa.
      _startArming();
    } else if (action == ResultsAction.next && nextId != null) {
      // Siguiente = ficha del siguiente paso (video guía), igual que desde el
      // catálogo. La ficha actual recibe el id y se sustituye a sí misma; así
      // "atrás" vuelve al catálogo y no a este paso. Abrir directamente otra
      // evaluación dejaba la cámara en negro: la nueva pantalla pedía la
      // cámara antes de que esta terminara de liberarla.
      context.pop(nextId);
    } else {
      context.pop();
    }
  }

  String? _nextStepId() {
    final steps = ref.read(catalogProvider).value;
    if (steps == null) return null;
    final i = steps.indexWhere((s) => s.id == widget.stepId);
    if (i < 0 || i + 1 >= steps.length) return null;
    return steps[i + 1].id;
  }

  @override
  void dispose() {
    _gesture.reset();
    _retryGesture.reset();
    _frames.dispose();
    _countdownToken++;
    _countdownTimer?.cancel();
    _goTimer?.cancel();
    _captureTimer?.cancel();
    _pulse.dispose();
    _musicPlayer.dispose();
    _tickPlayer.dispose();
    _goPlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_step?.nombre ?? 'Evaluación')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.preparing:
        return const _Centered(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Preparando referencia…'),
        ]));
      case _Phase.denied:
        return const _Centered(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Permiso de cámara denegado'),
            SizedBox(height: 12),
            FilledButton(
                onPressed: openAppSettings, child: Text('Abrir ajustes')),
          ]),
        );
      case _Phase.noVideo:
        return const _Centered(
          child: Text(
            'Este paso aún no tiene video de referencia.\nUsa el "Paso de prueba".',
            textAlign: TextAlign.center,
          ),
        );
      case _Phase.error:
        return _Centered(child: Text('Error: ${_error ?? ''}'));
      case _Phase.arming:
      case _Phase.countdown:
      case _Phase.capturing:
      case _Phase.computing:
      case _Phase.results:
        return _buildCamera();
    }
  }

  Widget _buildCamera() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _Centered(child: CircularProgressIndicator());
    }
    final isFront = _camera?.lensDirection == CameraLensDirection.front;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        RepaintBoundary(
          child: CustomPaint(
            painter: PosePainter(frames: _frames, isFront: isFront),
          ),
        ),
        if (_phase == _Phase.capturing)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LinearProgressIndicator(value: _progress),
            ),
          ),
        if (_phase == _Phase.results)
          const Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: _RetryHintChip(),
              ),
            ),
          ),
        if (_phase == _Phase.arming)
          ArmingOverlay(
            status: _arming,
            stillnessEnabled: _gesture.stillnessEnabled,
            onStartNow: _startCountdown,
          ),
        if (_phase == _Phase.countdown || _showGo)
          _CountdownOverlay(
            label: _showGo ? '¡YA!' : '$_countdown',
            isGo: _showGo,
            pulse: _pulse,
          ),
        if (_phase == _Phase.computing)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Evaluando…', style: TextStyle(color: Colors.white)),
            ]),
          ),
      ],
    );
  }
}

/// Conteo a pantalla completa: el numero ocupa todo el ancho disponible y
/// entra con un pulso para que se vea desde lejos mientras se baila (RF-08).
class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({
    required this.label,
    required this.isGo,
    required this.pulse,
  });

  final String label;
  final bool isGo;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    final color = isGo ? const Color(0xFF69F0AE) : Colors.white;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              radius: 0.9,
              colors: [Color(0xCC000000), Color(0xF2000000)],
            ),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final t = pulse.value.clamp(0.0, 1.0);
                // Entrada con rebote; el numero termina a tamano completo.
                final scale = 0.55 + 0.45 * Curves.easeOutBack.transform(t);
                final opacity = t < 0.12 ? t / 0.12 : 1.0;
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Column(
                    children: [
                      const Spacer(),
                      Expanded(
                        flex: 6,
                        child: Center(
                          child: Transform.scale(
                            scale: scale,
                            child: FractionallySizedBox(
                              widthFactor: 0.92,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 320,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -8,
                                    shadows: [
                                      Shadow(
                                        color: color.withValues(alpha: 0.6),
                                        blurRadius: 48,
                                      ),
                                      const Shadow(
                                        color: Colors.black87,
                                        blurRadius: 12,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Text(
                          isGo ? 'Baila' : 'Prepárate',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Recordatorio del gesto de reintento en la franja de cámara que deja libre
/// el modal de resultados.
class _RetryHintChip extends StatelessWidget {
  const _RetryHintChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.accessibility_new, color: Color(0xFF69F0AE), size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Manos en la cintura para reintentar',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: child));
}
