import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/pose_frame.dart';
import '../../domain/pose_landmarks.dart';
import '../../data/camera_input.dart';
import '../providers/pose_providers.dart';
import '../widgets/pose_painter.dart';

/// Preview de la cámara frontal en modo espejo con overlay del esqueleto
/// (RF-09) y validación de encuadre/confianza del tren inferior (RNF-05).
/// Recibe [stepId] para que la Fase 5 sepa qué paso evaluar.
class PosePage extends ConsumerStatefulWidget {
  const PosePage({super.key, required this.stepId});

  final String stepId;

  @override
  ConsumerState<PosePage> createState() => _PosePageState();
}

enum _Status { initializing, denied, running, error }

class _PosePageState extends ConsumerState<PosePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  _Status _status = _Status.initializing;
  String? _error;

  bool _busy = false; // un fotograma en proceso a la vez
  PoseFrame? _frame;

  // RNF-05: tren inferior con baja confianza sostenida > 1 s -> inválido.
  DateTime? _lowConfSince;
  bool _bodyInvalid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final granted = await Permission.camera.request();
    if (!granted.isGranted) {
      if (mounted) setState(() => _status = _Status.denied);
      return;
    }

    try {
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
      if (mounted) setState(() => _status = _Status.running);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _error = '$e';
        });
      }
    }
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
      _evaluateConfidence(frame);
      if (mounted) setState(() => _frame = frame);
    } catch (_) {
      // Fotograma descartado; el siguiente reintenta.
    } finally {
      _busy = false;
    }
  }

  void _evaluateConfidence(PoseFrame f) {
    var bad = !f.hasBody;
    if (f.hasBody) {
      for (final t in PoseLandmarks.lowerBodyCritical) {
        final lm = f.byType(t);
        if (lm == null || lm.confidence < PoseLandmarks.minConfidence) {
          bad = true;
          break;
        }
      }
    }
    final now = DateTime.now();
    if (bad) {
      _lowConfSince ??= now;
      if (now.difference(_lowConfSince!) > const Duration(seconds: 1)) {
        _bodyInvalid = true;
      }
    } else {
      _lowConfSince = null;
      _bodyInvalid = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara — pose')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.initializing:
        return const Center(child: CircularProgressIndicator());
      case _Status.denied:
        return const _Message(
          icon: Icons.no_photography_outlined,
          title: 'Permiso de cámara denegado',
          subtitle: 'Actívalo para usar la evaluación.',
          action: FilledButton(
            onPressed: openAppSettings,
            child: Text('Abrir ajustes'),
          ),
        );
      case _Status.error:
        return _Message(
          icon: Icons.error_outline,
          title: 'No se pudo abrir la cámara',
          subtitle: _error ?? '',
        );
      case _Status.running:
        return _buildPreview();
    }
  }

  Widget _buildPreview() {
    final controller = _controller!;
    final isFront = _camera?.lensDirection == CameraLensDirection.front;
    final frame = _frame;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        if (frame != null)
          CustomPaint(painter: PosePainter(frame: frame, isFront: isFront)),
        // Estado de detección.
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _StatusBanner(
            invalid: _bodyInvalid,
            hasBody: frame?.hasBody ?? false,
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.invalid, required this.hasBody});

  final bool invalid;
  final bool hasBody;

  @override
  Widget build(BuildContext context) {
    final (color, text, icon) = invalid || !hasBody
        ? (Colors.red.shade700,
            'Cuerpo no detectado — colócate completo a ≥ 1.4 m',
            Icons.warning_amber_rounded)
        : (Colors.green.shade700, 'Cuerpo detectado',
            Icons.check_circle_outline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
