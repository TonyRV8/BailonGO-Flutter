import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../../domain/step_animations.dart';
import '../controllers/model_viewer_controller.dart';

/// Degradado naranja del fondo del visor (Flutter detrás del WebView
/// transparente y CSS dentro de `<model-viewer>`, para que coincidan).
const _gradientColors = [
  Color(0xFFFFB74D),
  Color(0xFFFF8A3D),
  Color(0xFFE8590C)
];

const _viewerCss = '''
  model-viewer {
    background: linear-gradient(180deg, #FFB74D 0%, #FF8A3D 50%, #E8590C 100%);
    --poster-color: transparent;
    --progress-bar-color: #FFFFFF;
  }
''';

/// Avisa a Flutter cuando `<model-viewer>` termina de cargar el GLB (o falla).
/// Solo móvil: en web los `<script>` del HTML inyectado no se ejecutan.
const _channelName = 'Viewer3D';
const _viewerJs = '''
  (function () {
    var mv = document.querySelector('model-viewer');
    if (!mv || !window.$_channelName) return;
    mv.addEventListener('load', function () { $_channelName.postMessage('load'); });
    mv.addEventListener('error', function () { $_channelName.postMessage('error'); });
  })();
''';

/// Visor 3D del paso: maniquí con la animación del paso en bucle, cámara libre
/// (órbita, zoom, paneo), ángulos preestablecidos y control de velocidad.
///
/// Solo se abre desde la ficha del paso con [Step3DPage.route] (no tiene ruta
/// de go_router, así que no es accesible por URL ni desde el drawer). Sin
/// AppBar ni menús: se sale con "Regresar" o el gesto atrás del sistema, y al
/// salir se libera el renderizado (ver [ModelViewerController.release]).
class Step3DPage extends StatefulWidget {
  const Step3DPage({super.key, required this.step, this.title});

  /// Paso a mostrar: id del catálogo, nombre o alias ("basico",
  /// "right spot turn"…). Se traduce con [StepAnimations.forStep].
  final String step;

  /// Texto visible en la cabecera. Por defecto, [step].
  final String? title;

  static Route<void> route({required String step, String? title}) =>
      MaterialPageRoute<void>(
        builder: (_) => Step3DPage(step: step, title: title),
      );

  @override
  State<Step3DPage> createState() => _Step3DPageState();
}

class _Step3DPageState extends State<Step3DPage> with WidgetsBindingObserver {
  static const double _minSpeed = 0.25;
  static const double _maxSpeed = 2;

  late final String? _animation = StepAnimations.forStep(widget.step);
  final _viewer = ModelViewerController(minRadius: 0.6, maxRadius: 8);

  CameraPreset _preset = CameraPreset.front;
  double _speed = 1;

  // En web no hay canal JS que avise de la carga: se muestra directamente.
  bool _loaded = kIsWeb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_animation == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_viewer.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_viewer.pause());
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Respaldo: normalmente ya se liberó al iniciar el pop (ver PopScope), pero
    // la ruta también puede desaparecer sin pop (p. ej. cierre de sesión).
    unawaited(_viewer.release());
    super.dispose();
  }

  void _onViewerMessage(String message) {
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _failed = message == 'error';
    });
    // La velocidad pudo cambiarse mientras cargaba.
    if (!_failed && _speed != 1) unawaited(_viewer.setSpeed(_speed));
  }

  void _selectPreset(CameraPreset preset) {
    setState(() => _preset = preset);
    unawaited(_viewer.setCamera(preset));
  }

  void _changeSpeed(double speed) {
    setState(() => _speed = speed);
    unawaited(_viewer.setSpeed(speed));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Se libera al iniciar el pop (botón o gesto del sistema) y no en
      // dispose(), que llega tras la transición: así el WebView aún está vivo
      // para descargar el modelo y soltar el contexto WebGL.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_viewer.release());
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _gradientColors,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ModelViewer(
                src: StepAnimations.modelAsset,
                alt: 'Maniquí 3D bailando ${widget.title ?? widget.step}',
                loading: Loading.eager,
                backgroundColor: Colors.transparent,
                cameraControls: true,
                // Sin "tocar para recentrar": un toque accidental descuadraría
                // las vistas preestablecidas (el botón Recentrar las restaura).
                disableTap: true,
                touchAction: TouchAction.none,
                interactionPrompt: InteractionPrompt.none,
                cameraOrbit: CameraPreset.front.orbit,
                cameraTarget: CameraPreset.front.target,
                minCameraOrbit: 'auto auto ${_viewer.minRadius}m',
                maxCameraOrbit: 'auto 100deg ${_viewer.maxRadius}m',
                shadowIntensity: 1,
                animationName: _animation,
                autoPlay: _animation != null,
                relatedCss: _viewerCss,
                relatedJs: _viewerJs,
                javascriptChannels: {
                  JavascriptChannel(
                    _channelName,
                    onMessageReceived: (m) => _onViewerMessage(m.message),
                  ),
                },
                onWebViewCreated: _viewer.attach,
                debugLogging: false,
              ),
              if (!_loaded || _failed)
                Center(child: _LoadingPill(failed: _failed)),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: _TopBar(
                        title: widget.title ?? widget.step,
                        hasAnimation: _animation != null,
                        onBack: () => Navigator.maybePop(context),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ZoomControls(
                          onZoomIn: () => unawaited(_viewer.zoom(0.8)),
                          onZoomOut: () => unawaited(_viewer.zoom(1.25)),
                          onReset: () => _selectPreset(_preset),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _BottomPanel(
                        preset: _preset,
                        onPreset: _selectPreset,
                        speed: _speed,
                        minSpeed: _minSpeed,
                        maxSpeed: _maxSpeed,
                        onSpeed: _animation == null ? null : _changeSpeed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel oscuro translúcido, mismo estilo que los overlays de la evaluación.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.hasAnimation,
    required this.onBack,
  });

  final String title;
  final bool hasAnimation;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: onBack,
          style: FilledButton.styleFrom(
            // El tema usa botones a todo lo ancho (fromHeight); aquí es compacto.
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Regresar'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Glass(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  hasAnimation
                      ? 'Vista 3D · en bucle'
                      : 'Este paso aún no tiene animación 3D',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.all(4),
      radius: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundButton(
              icon: Icons.add, tooltip: 'Acercar', onPressed: onZoomIn),
          const SizedBox(height: 4),
          _RoundButton(
              icon: Icons.remove, tooltip: 'Alejar', onPressed: onZoomOut),
          const SizedBox(height: 4),
          _RoundButton(
            icon: Icons.center_focus_strong,
            tooltip: 'Recentrar cámara',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.preset,
    required this.onPreset,
    required this.speed,
    required this.minSpeed,
    required this.maxSpeed,
    required this.onSpeed,
  });

  final CameraPreset preset;
  final ValueChanged<CameraPreset> onPreset;
  final double speed;
  final double minSpeed;
  final double maxSpeed;

  /// `null` deshabilita el control (paso sin animación).
  final ValueChanged<double>? onSpeed;

  static const _icons = {
    CameraPreset.front: Icons.person,
    CameraPreset.right: Icons.east,
    CameraPreset.left: Icons.west,
    CameraPreset.back: Icons.flip_camera_android,
    CameraPreset.feet: Icons.directions_walk,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final white = theme.textTheme.bodyMedium?.copyWith(color: Colors.white);

    return _Glass(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      radius: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Velocidad', style: white),
              const Spacer(),
              Text(
                '${speed.toStringAsFixed(2)}x',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: speed,
            min: minSpeed,
            max: maxSpeed,
            // Pasos de 0.25x: 0.25, 0.5, …, 2.0.
            divisions: ((maxSpeed - minSpeed) / 0.25).round(),
            label: '${speed.toStringAsFixed(2)}x',
            onChanged: onSpeed,
          ),
          const SizedBox(height: 4),
          // Las 5 vistas siempre a la vista, a partes iguales (sin scroll).
          Row(
            children: [
              for (final p in CameraPreset.values) ...[
                Expanded(
                  child: _PresetButton(
                    label: p.label,
                    icon: _icons[p]!,
                    selected: p == preset,
                    onPressed: () => onPreset(p),
                  ),
                ),
                if (p != CameraPreset.values.last) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, 56),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      textStyle: Theme.of(context).textTheme.labelSmall,
    );
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ],
    );
    return selected
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      radius: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            const Icon(Icons.error_outline, color: Colors.white)
          else
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          const SizedBox(width: 12),
          Text(
            failed ? 'No se pudo cargar el modelo 3D' : 'Cargando modelo 3D…',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
