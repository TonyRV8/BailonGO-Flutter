import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../evaluation/presentation/widgets/reset_progress.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../tutorial/presentation/pages/tutorial_page.dart';
import '../../../viewer3d/domain/step_animations.dart';
import '../../domain/entities/step_stats.dart';
import '../../../viewer3d/presentation/pages/step_3d_page.dart';
import '../providers/catalog_providers.dart';

/// Ficha de un paso (RF-06): nombre, descripción, mejor precisión histórica y
/// el espacio del video del modelo ideal en bucle (RF-07).
class StepDetailPage extends ConsumerWidget {
  const StepDetailPage({super.key, required this.stepId});

  final String stepId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(stepByIdProvider(stepId));

    if (step == null) {
      // El catálogo aún no carga (deep-link directo a la ficha) o id inválido.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final stats = ref.watch(stepStatsProvider(stepId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(step.nombre)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _VideoPanel(mediaUrl: step.mediaUrl),
          const SizedBox(height: 16),
          Text(step.nombre, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16),
              const SizedBox(width: 4),
              Text('Duración: ${step.duracionCicloSeg.toStringAsFixed(0)} s',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          // Mejor precisión histórica (RF-06 / RN-04) e intentos realizados.
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Mejor precisión'),
                  trailing: _StatValue(
                    stats: stats,
                    text: (s) =>
                        s.best == null ? '—' : '${s.best!.toStringAsFixed(0)}%',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: const Text('Intentos realizados'),
                  trailing: _StatValue(
                    stats: stats,
                    text: (s) => '${s.attempts}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Descripción', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(step.descripcion, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          // Maniquí 3D del paso. Ruta imperativa (sin go_router) para que solo
          // se llegue desde aquí; el video guía se pausa mientras está encima.
          if (StepAnimations.forStep(step.id) != null) ...[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                Step3DPage.route(step: step.id, title: step.nombre),
              ),
              icon: const Icon(Icons.view_in_ar),
              label: const Text('Ver en 3D'),
            ),
            const SizedBox(height: 8),
          ],
          // Cámara + pose (Fase 3): preview espejo y esqueleto.
          FilledButton.tonalIcon(
            onPressed: () => context.push('${AppRoutes.pose}/${step.id}'),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Probar cámara (pose)'),
          ),
          const SizedBox(height: 8),
          // Evaluación end-to-end (RF-08+).
          FilledButton.icon(
            onPressed: () async {
              // La primera vez se enseña antes cómo colocarse y los gestos
              // (tutorial); si sale con el gesto atrás, no se evalúa.
              final settings = ref.read(currentSettingsProvider);
              if (!settings.tutorialSeen) {
                final go = await Navigator.of(context)
                    .push(TutorialPage.route(beforeEvaluation: true));
                await ref
                    .read(settingsControllerProvider.notifier)
                    .save(settings.copyWith(tutorialSeen: true));
                if (go != true || !context.mounted) return;
              }
              // La evaluación devuelve el id del siguiente paso si el usuario
              // pulsó "Siguiente": esta ficha se sustituye por la del
              // siguiente, como si se hubiera abierto desde el catálogo.
              final nextId = await context
                  .push<String>('${AppRoutes.evaluate}/${step.id}');
              if (nextId != null && context.mounted) {
                context.pushReplacement('${AppRoutes.step}/$nextId');
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar evaluación'),
          ),
          // Tutorial de uso (dónde poner el teléfono y los gestos).
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(TutorialPage.route()),
            icon: const Icon(Icons.help_outline),
            label: const Text('¿Cómo se usa la evaluación?'),
          ),
          // TEMPORAL (dev): reinicia la mejor marca de ESTE paso a 0. Mismo
          // botón que en Configuración para todos los pasos. Quitar en §8.
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => confirmAndResetProgress(
                context,
                ref,
                pasoId: step.id,
                stepName: step.nombre,
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reiniciar progreso de este paso (dev)'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Valor de una métrica del paso, con su estado de carga. Las dos métricas
/// salen del mismo provider, así que comparten spinner y error.
class _StatValue extends StatelessWidget {
  const _StatValue({required this.stats, required this.text});

  final AsyncValue<StepStats> stats;
  final String Function(StepStats) text;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const Text('—'),
      data: (s) =>
          Text(text(s), style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Video del modelo ideal en bucle (RF-07). Reproduce desde asset
/// (`assets/...`) o URL remota. Si no hay `mediaUrl`, muestra un marcador.
class _VideoPanel extends StatefulWidget {
  const _VideoPanel({required this.mediaUrl});

  final String? mediaUrl;

  @override
  State<_VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<_VideoPanel>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _controller;
  bool _failed = false;

  /// Otra pantalla (evaluación, cámara) está encima. El video guía lleva la
  /// música del paso: si siguiera sonando debajo, se oiría doble junto a la
  /// música de la evaluación.
  bool _covered = false;

  /// El usuario lo pausó con los controles: volver de otra pantalla o del
  /// segundo plano no debe reanudarlo por su cuenta.
  bool _userPaused = false;

  bool _muted = false;
  double _speed = 1;

  /// Ver el video como en un espejo, para quien aprende mejor así. Sólo
  /// cambia cómo se ve aquí: la evaluación compara contra la referencia de
  /// siempre.
  bool _mirrored = false;

  bool get _hasVideo => widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_hasVideo) _initVideo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  /// Se abre otra pantalla encima: el video se pausa (y con él su audio).
  @override
  void didPushNext() {
    _covered = true;
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      controller.pause();
    }
  }

  /// La ficha vuelve a ser visible (se cerró la evaluación): el bucle debe
  /// seguir corriendo sin que el usuario tenga que hacer nada.
  @override
  void didPopNext() {
    _covered = false;
    _resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volver del segundo plano con la evaluación abierta no debe reanudarlo.
    if (state == AppLifecycleState.resumed && !_covered) _resume();
  }

  /// Reanuda el bucle si quedó pausado. El reproductor de Android pausa al
  /// perder el foco de audio o al pasar a segundo plano, y no se reanuda solo.
  Future<void> _resume() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isPlaying ||
        _userPaused) {
      return;
    }
    try {
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      // Si el reproductor ya no es válido, se deja como está.
    }
  }

  Future<void> _initVideo() async {
    final url = widget.mediaUrl!;
    final controller = url.startsWith('assets/')
        ? VideoPlayerController.asset(url)
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      // El video lleva la música incrustada: suena y se repite con cada
      // vuelta del bucle (setLooping ya está activo).
      await controller.setVolume(1);
      // Si mientras cargaba ya se abrió la evaluación, no arrancar debajo.
      if (!_covered) await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      await controller.pause();
    } else {
      _userPaused = false;
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    await controller.setVolume(_muted ? 0 : 1);
  }

  Future<void> _setSpeed(double speed) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _speed = speed);
    await controller.setPlaybackSpeed(speed);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    // Las tomas están grabadas en vertical (720x1280). Se usa la relación de
    // aspecto REAL del video en vez de un 16/9 fijo, que dejaba el video
    // diminuto entre dos bandas muertas. Mientras carga se reserva 9/16 para
    // que el panel no dé un salto al aparecer el primer fotograma.
    final ratio = ready ? controller.value.aspectRatio : 9 / 16;
    // Tope de altura: un 9/16 a ancho completo ocuparía casi toda la pantalla y
    // empujaría título, descripción y botones fuera de vista.
    final maxHeight = MediaQuery.of(context).size.height * 0.55;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: ready
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        // Tocar el video también lo pausa o reanuda.
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Transform.flip(
                            flipX: _mirrored,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            ),
                          ),
                        ),
                        if (_mirrored)
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: _MirrorBadge(),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _VideoControls(
                            controller: controller,
                            muted: _muted,
                            speed: _speed,
                            mirrored: _mirrored,
                            onTogglePlay: _togglePlay,
                            onToggleMute: _toggleMute,
                            onToggleMirror: () =>
                                setState(() => _mirrored = !_mirrored),
                            onSpeed: _setSpeed,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _failed
                              ? Icons.error_outline
                              : Icons.videocam_outlined,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _failed
                              ? 'No se pudo reproducir el video'
                              : _hasVideo
                                  ? 'Cargando video…'
                                  : 'Video pendiente de grabación',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
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

/// Controles del video guía, sobre su parte de abajo: reproducir/pausar,
/// línea de tiempo arrastrable, velocidad y sonido. Se redibujan con el propio
/// [VideoPlayerController] (que es un ValueNotifier), no con la ficha entera.
class _VideoControls extends StatefulWidget {
  const _VideoControls({
    required this.controller,
    required this.muted,
    required this.speed,
    required this.mirrored,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onToggleMirror,
    required this.onSpeed,
  });

  final VideoPlayerController controller;
  final bool muted;
  final double speed;
  final bool mirrored;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleMirror;
  final ValueChanged<double> onSpeed;

  /// Velocidades disponibles: lentas para aprender el paso con calma.
  static const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  /// Posición mientras se arrastra la línea de tiempo (null si no se arrastra).
  double? _dragMs;

  /// Si estaba reproduciendo al empezar a arrastrar, para reanudar al soltar.
  bool _wasPlaying = false;

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _speedLabel(double v) =>
      '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString()}x';

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(
        color: white, fontFeatures: const [FontFeature.tabularFigures()]);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final totalMs = value.duration.inMilliseconds.toDouble();
          final posMs = _dragMs ??
              value.position.inMilliseconds.clamp(0, totalMs).toDouble();
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: white,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: white,
                  ),
                  child: SizedBox(
                    height: 24,
                    child: Slider(
                      value: totalMs > 0 ? posMs : 0,
                      max: totalMs > 0 ? totalMs : 1,
                      onChangeStart: (v) {
                        _wasPlaying = value.isPlaying;
                        widget.controller.pause();
                        setState(() => _dragMs = v);
                      },
                      onChanged: (v) {
                        setState(() => _dragMs = v);
                        widget.controller
                            .seekTo(Duration(milliseconds: v.round()));
                      },
                      onChangeEnd: (v) async {
                        await widget.controller
                            .seekTo(Duration(milliseconds: v.round()));
                        if (_wasPlaying) await widget.controller.play();
                        if (mounted) setState(() => _dragMs = null);
                      },
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onTogglePlay,
                      tooltip: value.isPlaying ? 'Pausar' : 'Reproducir',
                      color: white,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    Text(
                      '${_fmt(Duration(milliseconds: posMs.round()))} / '
                      '${_fmt(value.duration)}',
                      style: small,
                    ),
                    const Spacer(),
                    PopupMenuButton<double>(
                      tooltip: 'Velocidad',
                      initialValue: widget.speed,
                      onSelected: widget.onSpeed,
                      itemBuilder: (_) => [
                        for (final v in _VideoControls.speeds)
                          PopupMenuItem(value: v, child: Text(_speedLabel(v))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed, color: white, size: 20),
                            const SizedBox(width: 4),
                            Text(_speedLabel(widget.speed), style: small),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onToggleMirror,
                      tooltip: widget.mirrored
                          ? 'Quitar modo espejo'
                          : 'Ver en modo espejo',
                      color: widget.mirrored ? _MirrorBadge.color : white,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.flip),
                    ),
                    IconButton(
                      onPressed: widget.onToggleMute,
                      tooltip: widget.muted ? 'Activar sonido' : 'Silenciar',
                      color: white,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                          widget.muted ? Icons.volume_off : Icons.volume_up),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Aviso sobre el video cuando se ve en modo espejo, para que no se confunda
/// la izquierda de la profesora con la propia.
class _MirrorBadge extends StatelessWidget {
  const _MirrorBadge();

  static const color = Color(0xFFFFD54F);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flip, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              'Modo espejo',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
