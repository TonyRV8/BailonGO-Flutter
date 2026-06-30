import 'package:flutter/material.dart';

import '../../engine/dtw_result.dart';

enum ResultsAction { exit, next }

/// Modal de resultados (RF-10): ritmo, alineación, precisión total y feedback
/// cualitativo, con controles Salir / Siguiente paso (RF-11).
class ResultsSheet extends StatelessWidget {
  const ResultsSheet({
    super.key,
    required this.result,
    required this.feedback,
    required this.hasNext,
  });

  final DtwResult result;
  final String feedback;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text('Resultado', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 4),
            const Center(child: Text('Precisión total')),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _Metric(
                        label: 'Alineación', value: result.alignmentScore)),
                Expanded(
                    child: _Metric(label: 'Ritmo', value: result.rhythmScore)),
              ],
            ),
            const SizedBox(height: 20),
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
                  Expanded(child: Text(feedback)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
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
                  child: FilledButton(
                    onPressed: hasNext
                        ? () => Navigator.of(context).pop(ResultsAction.next)
                        : null,
                    child: const Text('Siguiente paso'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 70) return Colors.green;
    if (score >= 45) return Colors.orange;
    return Colors.red;
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
