import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/router/app_routes.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/dance_step.dart';
import '../providers/catalog_providers.dart';
import '../widgets/step_visuals.dart';

/// Listado completo de los 9 pasos WSF Bronce (RF-05), en cuadrícula de
/// pósters verticales con la toma completa de la profesora.
///
/// Como las miniaturas de YouTube: el póster que queda a la vista cuando el
/// usuario deja de desplazarse reproduce el video sin sonido, y mantenerlo
/// pulsado también lo reproduce. Sólo uno a la vez.
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  /// Tiempo quieto sobre un póster antes de que empiece su vista previa.
  static const previewDelay = Duration(milliseconds: 900);

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage>
    with WidgetsBindingObserver {
  /// Paso que reproduce su vista previa ahora (null = ninguno).
  final ValueNotifier<String?> _previewing = ValueNotifier(null);
  final Map<String, GlobalKey> _keys = {};
  final GlobalKey _viewportKey = GlobalKey();
  Timer? _pickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pickTimer?.cancel();
    _previewing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedulePick();
    } else {
      _stopPreview();
    }
  }

  void _stopPreview() {
    _pickTimer?.cancel();
    _previewing.value = null;
  }

  /// Tras un rato sin desplazarse, reproduce el póster más visible.
  void _schedulePick() {
    _pickTimer?.cancel();
    _pickTimer = Timer(CatalogPage.previewDelay, _pickMostVisible);
  }

  void _pickMostVisible() {
    if (!mounted) return;
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final view = Offset.zero & viewport.size;
    String? bestId;
    var bestScore = 0.0;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final rect =
          box.localToGlobal(Offset.zero, ancestor: viewport) & box.size;
      final visible = rect.intersect(view);
      if (visible.width <= 0 || visible.height <= 0) continue;
      final fraction =
          visible.width * visible.height / (rect.width * rect.height);
      if (fraction < 0.85) continue;
      // Entre los que se ven completos gana el más cercano al centro; en
      // empate, el primero (izquierda, arriba).
      final dist = (rect.center - view.center).distance;
      final score = fraction * 1000 - dist;
      if (bestId == null || score > bestScore) {
        bestId = e.key;
        bestScore = score;
      }
    }
    _previewing.value = bestId;
  }

  Future<void> _open(DanceStep step) async {
    _stopPreview();
    await context.push('${AppRoutes.step}/${step.id}');
    if (mounted) _schedulePick();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CatalogError(
        message: '$e',
        onRetry: () => ref.invalidate(catalogProvider),
      ),
      data: (steps) {
        for (final s in steps) {
          _keys.putIfAbsent(s.id, GlobalKey.new);
        }
        // Primera vista previa en cuanto se dibuja el catálogo.
        if (_previewing.value == null && _pickTimer == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePick());
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification) {
              _stopPreview();
            } else if (n is ScrollEndNotification) {
              _schedulePick();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(catalogProvider);
              ref.invalidate(userStepStatsProvider);
            },
            child: CustomScrollView(
              key: _viewportKey,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _Summary(steps: steps)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // Vertical como la toma, para que se vea la bailarina
                      // completa.
                      childAspectRatio: 9 / 14,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final step = steps[i];
                        return ValueListenableBuilder<String?>(
                          key: _keys[step.id],
                          valueListenable: _previewing,
                          builder: (_, active, __) => _PosterCard(
                            step: step,
                            previewing: active == step.id,
                            onTap: () => _open(step),
                            onLongPress: () {
                              _pickTimer?.cancel();
                              _previewing.value = step.id;
                            },
                          ),
                        );
                      },
                      childCount: steps.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "3 de 9 pasos aprendidos" con su barra.
class _Summary extends ConsumerWidget {
  const _Summary({required this.steps});
  final List<DanceStep> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(userStepStatsProvider).value ?? const {};
    final threshold = ref.watch(currentSettingsProvider).learnedThreshold;
    final learned = steps
        .where((s) =>
            StepProgress.of(stats[s.id]?.best, threshold) ==
            StepProgress.learned)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$learned de ${steps.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: ' pasos aprendidos'),
            ]),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: steps.isEmpty ? 0 : learned / steps.length,
              minHeight: 6,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Póster de un paso: toma vertical, estado, mejor marca, nombre y frase.
/// Con [previewing] reproduce el video del paso sin sonido sobre la portada.
class _PosterCard extends ConsumerStatefulWidget {
  const _PosterCard({
    required this.step,
    required this.previewing,
    required this.onTap,
    required this.onLongPress,
  });

  final DanceStep step;
  final bool previewing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  ConsumerState<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<_PosterCard> {
  VideoPlayerController? _video;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (widget.previewing) _startPreview();
  }

  @override
  void didUpdateWidget(_PosterCard old) {
    super.didUpdateWidget(old);
    if (widget.previewing != old.previewing) {
      widget.previewing ? _startPreview() : _stopPreview();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _startPreview() async {
    final url = widget.step.mediaUrl;
    if (url == null || !url.startsWith('assets/') || _video != null) return;
    // Sin sonido y sin cortar la música que el usuario tenga puesta.
    final video = VideoPlayerController.asset(
      url,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = video;
    try {
      await video.initialize();
      await video.setVolume(0);
      await video.setLooping(true);
      if (!mounted || _video != video) return;
      await video.play();
      if (mounted && _video == video) setState(() => _playing = true);
    } catch (_) {
      if (_video == video) _stopPreview();
    }
  }

  void _stopPreview() {
    final video = _video;
    _video = null;
    if (mounted) setState(() => _playing = false);
    video?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final stats = ref.watch(userStepStatsProvider).value?[step.id];
    final threshold = ref.watch(currentSettingsProvider).learnedThreshold;
    final best = stats?.best;
    final progress = StepProgress.of(best, threshold);
    final video = _video;

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StepThumbnail(step: step),
            // El video entra con un fundido sobre la portada cuando ya tiene
            // imagen, para que no parpadee en negro.
            AnimatedOpacity(
              opacity: _playing ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: video != null && video.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.3),
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: video.value.size.width,
                        height: video.value.size.height,
                        child: VideoPlayer(video),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Degradado inferior para que el texto se lea sobre la foto.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0, 0.38, 0.65],
                  colors: [
                    Color(0xF2140C0E),
                    Color(0x55140C0E),
                    Color(0x00000000)
                  ],
                ),
              ),
            ),
            Positioned(top: 8, left: 8, child: StatusTag(progress)),
            if (best != null)
              Positioned(
                top: 6,
                right: 6,
                child: ProgressRing(percent: best, color: progress.color),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stepTagline(step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('No se pudo cargar el catálogo',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
