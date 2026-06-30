import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/app_routes.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../catalog/domain/entities/dance_step.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../pose/data/camera_input.dart';
import '../../../pose/domain/entities/pose_frame.dart';
import '../../../pose/presentation/providers/pose_providers.dart';
import '../../../pose/presentation/widgets/pose_painter.dart';
import '../../domain/evaluation_feedback.dart';
import '../../engine/dtw_comparator.dart';
import '../../engine/dtw_result.dart';
import '../../engine/feature_extractor.dart';
import '../providers/evaluation_providers.dart';
import '../widgets/results_sheet.dart';

/// La referencia se extrae con isMirrored=false; la captura en vivo se procesa
/// igual (raw NV21, sin flip) para que coincidan. Si la lateralidad sale
/// invertida en device, poner en true.
const bool _mirrorLiveCapture = false;

enum _Phase { preparing, noVideo, ready, countdown, capturing, computing, error, denied }

/// Flujo de evaluación end-to-end (RF-08..RF-11).
class EvaluationPage extends ConsumerStatefulWidget {
  const EvaluationPage({super.key, required this.stepId});

  final String stepId;

  @override
  ConsumerState<EvaluationPage> createState() => _EvaluationPageState();
}

class _EvaluationPageState extends ConsumerState<EvaluationPage> {
  CameraController? _controller;
  CameraDescription? _camera;

  _Phase _phase = _Phase.preparing;
  String? _error;

  DanceStep? _step;
  List<List<double>> _refFrames = const [];

  bool _busy = false;
  PoseFrame? _frame;
  final List<List<double>> _userFrames = [];

  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _captureTimer;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _init();
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
      setState(() => _phase = refFrames.isEmpty ? _Phase.noVideo : _Phase.ready);
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
    _busy = true;
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
        final v = FeatureExtractor.extractFeatures(
          frame.landmarks,
          isMirrored: _mirrorLiveCapture,
        );
        if (v != null) _userFrames.add(v);
      }
      if (mounted) setState(() => _frame = frame);
    } catch (_) {
      // Fotograma descartado.
    } finally {
      _busy = false;
    }
  }

  void _startCountdown() {
    setState(() {
      _countdown = 3;
      _phase = _Phase.countdown;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        _startCapture();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _startCapture() {
    _userFrames.clear();
    // Captura sincronizada con la duración real del video guía (RN-07):
    // la referencia se muestrea cada 33 ms (~30 fps).
    final durationMs =
        (_refFrames.length * 33).clamp(1000, 60000).toInt();
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

  Future<void> _finishCapture() async {
    setState(() => _phase = _Phase.computing);
    final result = DtwComparator.compare(
      _userFrames,
      _refFrames,
      weights: _step?.weights,
    );

    // Guardar intento (RN-04: la mejor marca se deriva del máximo en HISTORY).
    final user = ref.read(currentUserProvider);
    if (user.isNotEmpty) {
      try {
        await ref.read(attemptRepositoryProvider).save(
              uid: user.uid,
              pasoId: widget.stepId,
              result: result,
            );
        ref.invalidate(bestScoreProvider(widget.stepId));
      } catch (_) {
        // Sin red: el intento se mostrará igual; sync queda para Fase 7.
      }
    }

    if (mounted) _showResults(result);
  }

  Future<void> _showResults(DtwResult result) async {
    final nextId = _nextStepId();
    final action = await showModalBottomSheet<ResultsAction>(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      builder: (_) => ResultsSheet(
        result: result,
        feedback: feedbackFor(result),
        hasNext: nextId != null,
      ),
    );

    if (!mounted) return;
    if (action == ResultsAction.next && nextId != null) {
      context.pushReplacement('${AppRoutes.evaluate}/$nextId');
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
    _countdownTimer?.cancel();
    _captureTimer?.cancel();
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
        return _Centered(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Permiso de cámara denegado'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: openAppSettings, child: const Text('Abrir ajustes')),
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
      case _Phase.ready:
      case _Phase.countdown:
      case _Phase.capturing:
      case _Phase.computing:
        return _buildCamera();
    }
  }

  Widget _buildCamera() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _Centered(child: CircularProgressIndicator());
    }
    final isFront = _camera?.lensDirection == CameraLensDirection.front;
    final frame = _frame;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        if (frame != null)
          CustomPaint(painter: PosePainter(frame: frame, isFront: isFront)),
        if (_phase == _Phase.capturing)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LinearProgressIndicator(value: _progress),
            ),
          ),
        if (_phase == _Phase.countdown)
          Container(
            color: Colors.black38,
            alignment: Alignment.center,
            child: Text('$_countdown',
                style: const TextStyle(
                    color: Colors.white, fontSize: 120, fontWeight: FontWeight.bold)),
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
        if (_phase == _Phase.ready)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.icon(
                onPressed: _startCountdown,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar evaluación'),
              ),
            ),
          ),
      ],
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
