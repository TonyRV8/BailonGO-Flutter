import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../pose/presentation/pages/laterality_check_page.dart';
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
          ref.invalidate(userStepStatsProvider);
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          // La primera ficha es la prueba de lateralidad, no un paso.
          itemCount: steps.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              i == 0 ? const _LateralityCard() : _StepCard(step: steps[i - 1]),
        ),
      ),
    );
  }
}

/// Acceso a la comprobación de izquierda/derecha. Va arriba del catálogo
/// porque conviene pasarla una vez por teléfono, antes de evaluar: si los
/// lados salen cambiados, los consejos de la evaluación hablan del lado
/// equivocado.
class _LateralityCard extends StatelessWidget {
  const _LateralityCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        leading: Icon(Icons.swap_horiz,
            color: theme.colorScheme.onSecondaryContainer),
        title: Text(
          'Comprobar izquierda y derecha',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        subtitle: Text(
          'Levanta el brazo derecho y confirma que la app lo reconoce.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: theme.colorScheme.onSecondaryContainer),
        onTap: () =>
            Navigator.of(context).push(LateralityCheckPage.route()),
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
    final stats = ref.watch(userStepStatsProvider).value?[step.id];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('${AppRoutes.step}/${step.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cover(step: step),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.nombre,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ProgressBar(
                    best: stats?.best,
                    attempts: stats?.attempts ?? 0,
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

/// Portada ancha: frame del video de referencia si existe; si no, el número.
class _Cover extends ConsumerWidget {
  const _Cover({required this.step});
  final DanceStep step;

  static const double _height = 170;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget number() => Container(
          height: _height,
          color: theme.colorScheme.primaryContainer,
          alignment: Alignment.center,
          child: Text('${step.orden}',
              style: theme.textTheme.displayMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
        );

    if (!step.hasVideo) return number();

    return ref.watch(stepThumbnailProvider(step.mediaUrl!)).maybeWhen(
          data: (bytes) => bytes == null
              ? number()
              : Image.memory(bytes,
                  height: _height, width: double.infinity, fit: BoxFit.cover),
          orElse: () => Container(
            height: _height,
            color: theme.colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
        );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({this.best, this.attempts = 0});
  final double? best;

  /// Intentos evaluados de este paso (métrica de uso, se deriva de HISTORY).
  final int attempts;

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
          b == null
              ? 'Sin intentos'
              : 'Mejor: ${b.toStringAsFixed(0)}%  ·  '
                  '$attempts ${attempts == 1 ? 'intento' : 'intentos'}',
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
