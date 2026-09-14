import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/app_routes.dart';
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

    final bestScore = ref.watch(bestScoreProvider(stepId));
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
              Text('Ciclo: ${step.duracionCicloSeg.toStringAsFixed(0)} s',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          // Mejor precisión histórica (RF-06 / RN-04).
          Card(
            child: ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Mejor precisión'),
              trailing: bestScore.when(
                loading: () => const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Text('—'),
                data: (score) => Text(
                  score == null ? '—' : '${score.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Descripción', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(step.descripcion, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          // Cámara + pose (Fase 3): preview espejo y esqueleto.
          FilledButton.tonalIcon(
            onPressed: () => context.push('${AppRoutes.pose}/${step.id}'),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Probar cámara (pose)'),
          ),
          const SizedBox(height: 8),
          // Evaluación end-to-end (RF-08+).
          FilledButton.icon(
            onPressed: () => context.push('${AppRoutes.evaluate}/${step.id}'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar evaluación'),
          ),
        ],
      ),
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

  bool get _hasVideo =>
      widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty;

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

  /// La ficha vuelve a ser visible (se cerró la evaluación): el bucle debe
  /// seguir corriendo sin que el usuario tenga que hacer nada.
  @override
  void didPopNext() => _resume();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume();
  }

  /// Reanuda el bucle si quedó pausado. El reproductor de Android pausa al
  /// perder el foco de audio o al pasar a segundo plano, y no se reanuda solo.
  Future<void> _resume() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isPlaying) {
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
      await controller.setVolume(0); // bucle silencioso, es referencia visual
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
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

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: ready
              ? FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
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
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
