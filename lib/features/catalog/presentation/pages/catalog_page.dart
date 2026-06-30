import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../domain/entities/dance_step.dart';
import '../providers/catalog_providers.dart';

/// Listado completo de los 9 pasos WSF Bronce (RF-05).
class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CatalogError(
        message: '$e',
        onRetry: () => ref.invalidate(catalogProvider),
      ),
      data: (steps) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(catalogProvider);
          ref.invalidate(userBestScoresProvider);
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: steps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _StepCard(step: steps[i]),
        ),
      ),
    );
  }
}

class _StepCard extends ConsumerWidget {
  const _StepCard({required this.step});
  final DanceStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final best = ref.watch(userBestScoresProvider).value?[step.id];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('${AppRoutes.step}/${step.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Cover(step: step),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.nombre,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    _ProgressBar(best: best),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Portada: frame del video de referencia si existe; si no, el número del paso.
class _Cover extends ConsumerWidget {
  const _Cover({required this.step});
  final DanceStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget number() => Container(
          width: 64,
          height: 64,
          color: theme.colorScheme.primaryContainer,
          alignment: Alignment.center,
          child: Text('${step.orden}',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
        );

    final cover = !step.hasVideo
        ? number()
        : ref.watch(stepThumbnailProvider(step.mediaUrl!)).maybeWhen(
              data: (bytes) => bytes == null
                  ? number()
                  : Image.memory(bytes,
                      width: 64, height: 64, fit: BoxFit.cover),
              orElse: number,
            );

    return ClipRRect(borderRadius: BorderRadius.circular(10), child: cover);
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({this.best});
  final double? best;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = best;
    final value = (b ?? 0) / 100;
    final color = b == null
        ? theme.colorScheme.outline
        : (b >= 80 ? Colors.green : Colors.orange);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          b == null ? 'Sin intentos' : 'Mejor: ${b.toStringAsFixed(0)}%',
          style: theme.textTheme.bodyMedium,
        ),
      ],
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
            FilledButton.tonal(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
