import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../providers/evaluation_providers.dart';

/// TEMPORAL (dev): pide confirmación y borra los intentos del usuario de un
/// paso ([pasoId]) o de todos (`null`), dejando la mejor marca en 0. Lo usan
/// la ficha de cada paso y Configuración. Quitar antes de entregar (§8).
Future<void> confirmAndResetProgress(
  BuildContext context,
  WidgetRef ref, {
  String? pasoId,
  String? stepName,
}) async {
  final scope = pasoId == null ? 'de TODOS los pasos' : 'de "$stepName"';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Reiniciar progreso?'),
      content: Text('Se eliminarán todos tus intentos $scope y la mejor marca '
          'volverá a 0. No se puede deshacer.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reiniciar')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final uid = ref.read(currentUserProvider).uid;
    if (uid.isEmpty) return;
    final count = await ref
        .read(attemptRepositoryProvider)
        .deleteAttempts(uid: uid, pasoId: pasoId);
    // Ficha del paso, catálogo y progreso del perfil.
    ref.invalidate(bestScoreProvider);
    ref.invalidate(userBestScoresProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Progreso reiniciado: $count intentos borrados.')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error al reiniciar: $e')));
  }
}
