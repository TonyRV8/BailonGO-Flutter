import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../evaluation/presentation/widgets/reset_progress.dart';
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
              Text('Duración: ${step.duracionCicloSeg.toStringAsFixed(0)} s',
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
            onPressed: () async {
              // La evaluación devuelve el id del siguiente paso si el usuario
              // pulsó "Siguiente": esta ficha se sustituye por la del
              // siguiente, como si se hubiera abierto desde el catálogo.
              final nextId =
                  await context.push<String>('${AppRoutes.evaluate}/${step.id}');
              if (nextId != null && context.mounted) {
                context.pushReplacement('${AppRoutes.step}/$nextId');
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar evaluación'),
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
