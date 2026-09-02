import 'package:flutter/material.dart';

import '../../domain/evaluation_feedback.dart';
import '../../engine/dtw_result.dart';

enum ResultsAction { exit, retry, next }

/// Modal de resultados (RF-10): precisión total + desglose en los 3 tiempos
/// del paso (inicio/medio/final) con alineación, ritmo y consejos específicos
/// por tiempo. Controles Salir / Reintentar / Siguiente paso (RF-11).
class ResultsSheet extends StatelessWidget {
  const ResultsSheet({
    super.key,
    required this.result,
    required this.feedback,
    required this.hasNext,
  });

  final DtwResult result;
  final EvaluationFeedback feedback;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                children: [
                  Center(
                    child: Text('Resultado', style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: 12),
                  // Precisión total (RNF-06).
                  Center(
                    child: Text(
                      '${result.score}%',
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: _scoreColor(result.score),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Center(child: Text('Precisión total')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                            label: 'Alineación', value: result.alignmentScore),
                      ),
                      Expanded(
                        child:
                            _Metric(label: 'Ritmo', value: result.rhythmScore),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(feedback.overall)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Desglose por tiempo',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final seg in feedback.segments) ...[
                    _SegmentCard(segment: seg),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(ResultsAction.exit),
                      child: const Text('Salir'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          Navigator.of(context).pop(ResultsAction.retry),
                      icon: const Icon(Icons.replay),
                      label: const Text('Reintentar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: hasNext
                          ? () => Navigator.of(context).pop(ResultsAction.next)
                          : null,
                      child: const Text('Siguiente'),
                    ),
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

/// Tarjeta de un tiempo del paso: precisión, alineación, ritmo y consejos.
class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.segment});

  final SegmentFeedback segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  segment.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${segment.score}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _scoreColor(segment.score),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniBar(
                    label: 'Alineación', value: segment.alignmentScore),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniBar(label: 'Ritmo', value: segment.rhythmScore),
              ),
            ],
          ),
          if (segment.tips.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final tip in segment.tips)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                        child:
                            Text(tip, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Text('¡Este tiempo salió muy bien!',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label $value%', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 6,
            color: _scoreColor(value),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$value%', style: theme.textTheme.headlineSmall),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

Color _scoreColor(int score) {
  if (score >= 70) return Colors.green;
  if (score >= 45) return Colors.orange;
  return Colors.red;
}
