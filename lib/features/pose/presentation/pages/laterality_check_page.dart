import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/camera_input.dart';
import '../../domain/entities/pose_frame.dart';
import '../../domain/laterality.dart';
import '../providers/pose_providers.dart';
import '../widgets/pose_painter.dart';

/// Comprobación de lateralidad: ¿la app ve tu lado derecho como derecho?
///
/// Algunos teléfonos entregan el fotograma de la cámara frontal ya volteado y
/// otros no, así que el mismo gesto puede leerse al revés según el aparato. Eso
/// no afecta a la nota global (el motor detecta el espejo), pero sí a los
/// consejos: decirle a alguien que levante más la rodilla equivocada es peor
/// que no decirle nada.
///
/// La prueba pide levantar el brazo DERECHO y compara el lado que reporta
/// MediaPipe con el que debería ser. Si no coinciden, ofrece activar (o
/// desactivar) "Corregir lateralidad" en Configuración, que es el interruptor
/// que usa la evaluación.
class LateralityCheckPage extends ConsumerStatefulWidget {
  const LateralityCheckPage({super.key});

  /// Ruta imperativa: solo se llega desde el catálogo.
  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const LateralityCheckPage(),
      );

  @override
  ConsumerState<LateralityCheckPage> createState() =>
      _LateralityCheckPageState();
}

enum _Status { initializing, denied, running, error }

class _LateralityCheckPageState extends ConsumerState<LateralityCheckPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  _Status _status = _Status.initializing;
  String? _error;
  bool _permanentlyDenied = false;

  bool _busy = false;
  final ValueNotifier<PoseFrame> _frames = ValueNotifier(PoseFrame.empty);

  /// Lado detectado de forma sostenida y desde cuándo. Un fotograma suelto no
  /// decide nada: el detector se equivoca al cruzar los brazos o al entrar en
  /// cuadro.
  RaisedSide _side = RaisedSide.none;
  DateTime? _sideSince;

  /// Veredicto, una vez que el brazo se mantuvo arriba [_holdMs].
  RaisedSide? _verdict;

  static const int _holdMs = 800;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _frames.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
      if (mounted) setState(() => _status = _Status.initializing);
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _status = _Status.denied;
          _permanentlyDenied = status.isPermanentlyDenied || status.isRestricted;
        });
      }
      return;
    }
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        throw StateError(Platform.isIOS
            ? 'No hay cámara disponible. El simulador de iOS no tiene; prueba '
                'en un iPhone real.'
            : 'No hay cámara disponible en este dispositivo.');
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      _camera = front;
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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
            mirrored: data.mirrored,
          );
      if (!mounted) return;
      _frames.value = frame;
      _evaluate(frame);
    } catch (_) {
      // Fotograma descartado; el siguiente reintenta.
    } finally {
      _busy = false;
    }
  }

  void _evaluate(PoseFrame f) {
    if (_verdict != null) return; // ya hay resultado; espera a "Repetir"
    final raw = Laterality.raisedArm(f);
    // El motor compara con la referencia aplicando "Corregir lateralidad"
    // (users.settings.mirrorCapture): si está activo, los lados se
    // intercambian, así que la prueba debe medir lo mismo que la evaluación.
    final side = Laterality.asEvaluated(raw,
        mirrored: ref.read(currentSettingsProvider).mirrorCapture);

    if (side != _side) {
      setState(() {
        _side = side;
        _sideSince = (side == RaisedSide.left || side == RaisedSide.right)
            ? DateTime.now()
            : null;
      });
      return;
    }
    final since = _sideSince;
    if (since == null) return;
    if (DateTime.now().difference(since).inMilliseconds >= _holdMs) {
      setState(() => _verdict = side);
    }
  }

  void _reset() {
    setState(() {
      _verdict = null;
      _side = RaisedSide.none;
      _sideSince = null;
    });
  }

  /// Invierte "Corregir lateralidad" y deja la prueba lista para repetirse.
  Future<void> _fix() async {
    final settings = ref.read(currentSettingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(settingsControllerProvider.notifier)
        .save(settings.copyWith(mirrorCapture: !settings.mirrorCapture));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Corregir lateralidad: '
            '${!settings.mirrorCapture ? 'activado' : 'desactivado'}. '
            'Repite la prueba para confirmar.'),
      ),
    );
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Izquierda y derecha')),
      body: switch (_status) {
        _Status.initializing => const Center(child: CircularProgressIndicator()),
        _Status.denied => _DeniedBody(
            permanent: _permanentlyDenied,
            onRetry: () {
              setState(() => _status = _Status.initializing);
              _start();
            },
          ),
        _Status.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No se pudo abrir la cámara\n${_error ?? ''}',
                  textAlign: TextAlign.center),
            ),
          ),
        _Status.running => _buildRunning(),
      },
    );
  }

  Widget _buildRunning() {
    final controller = _controller!;
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
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(child: _Banner(side: _side, verdict: _verdict)),
        ),
        if (_verdict != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: _Result(
                ok: _verdict == RaisedSide.right,
                mirrorOn: ref.watch(currentSettingsProvider).mirrorCapture,
                onRepeat: _reset,
                onFix: _fix,
              ),
            ),
          ),
      ],
    );
  }
}

/// Instrucción mientras la prueba corre.
class _Banner extends StatelessWidget {
  const _Banner({required this.side, required this.verdict});

  final RaisedSide side;
  final RaisedSide? verdict;

  @override
  Widget build(BuildContext context) {
    if (verdict != null) return const SizedBox.shrink();
    final text = switch (side) {
      RaisedSide.both => 'Baja un brazo: levanta solo el DERECHO.',
      RaisedSide.none => 'Ponte de frente y levanta tu brazo DERECHO.',
      _ => 'Mantenlo arriba…',
    };
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Veredicto: coincide o está invertido.
class _Result extends StatelessWidget {
  const _Result({
    required this.ok,
    required this.mirrorOn,
    required this.onRepeat,
    required this.onFix,
  });

  final bool ok;
  final bool mirrorOn;
  final VoidCallback onRepeat;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok ? Colors.green : theme.colorScheme.error;
    return Card(
      margin: const EdgeInsets.all(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? 'Lateralidad correcta'
                        : 'Lateralidad invertida',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ok
                  ? 'La app vio tu brazo derecho como derecho. Los consejos de '
                      'la evaluación te hablarán del lado correcto.'
                  : 'Levantaste el brazo derecho y la app lo leyó como el '
                      'izquierdo. En la evaluación los consejos saldrían con '
                      'el lado cambiado.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: onRepeat, child: const Text('Repetir')),
                const Spacer(),
                if (!ok)
                  FilledButton(
                    onPressed: onFix,
                    child: Text(mirrorOn
                        ? 'Desactivar corrección'
                        : 'Corregir lateralidad'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeniedBody extends StatelessWidget {
  const _DeniedBody({required this.permanent, required this.onRetry});

  final bool permanent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Permiso de cámara denegado'),
            const SizedBox(height: 4),
            Text(
              permanent
                  ? 'Actívalo en Ajustes › BailonGO › Cámara.'
                  : 'La prueba necesita ver tu cuerpo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (permanent)
              const FilledButton(
                  onPressed: openAppSettings, child: Text('Abrir ajustes'))
            else
              FilledButton(
                  onPressed: onRetry, child: const Text('Permitir cámara')),
          ],
        ),
      ),
    );
  }
}
