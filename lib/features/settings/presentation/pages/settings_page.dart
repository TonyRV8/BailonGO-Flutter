import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_constants.dart';
import '../../../evaluation/presentation/widgets/reset_progress.dart';
import '../../../tutorial/presentation/pages/tutorial_page.dart';
import '../providers/settings_providers.dart';

/// Configuración (RF-01): preferencias del usuario persistidas en
/// `users.settings` + herramientas de desarrollo (solo debug).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.settings_outlined,
            size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Center(
          child: Text('Configuración',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 24),
        Text('Evaluación', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Umbral de "Paso Aprendido" (RN-02), configurable.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.school_outlined),
          title: const Text('Umbral de "Aprendido"'),
          subtitle: Text(
              'Un paso cuenta como aprendido con una mejor marca ≥ '
              '${settings.learnedThreshold.toStringAsFixed(0)}%.'),
        ),
        Slider(
          value: settings.learnedThreshold.clamp(50, 100),
          min: 50,
          max: 100,
          divisions: 10,
          label: '${settings.learnedThreshold.toStringAsFixed(0)}%',
          onChanged: (v) =>
              controller.save(settings.copyWith(learnedThreshold: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.flip_outlined),
          title: const Text('Corregir lateralidad (espejo)'),
          subtitle: const Text(
              'Actívalo si la evaluación confunde tu lado izquierdo y derecho.'),
          value: settings.mirrorCapture,
          onChanged: (v) =>
              controller.save(settings.copyWith(mirrorCapture: v)),
        ),
        // Arranque automático por quietud (RF-08.3). Desactivable para probar
        // solo el gesto de brazos arriba.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.self_improvement_outlined),
          title: const Text('Iniciar al quedarme quieto'),
          subtitle: const Text(
              'La cuenta regresiva arranca tras '
              '${AppConstants.stillnessSeconds} s sin moverte, ya encuadrado. '
              'Si lo desactivas, solo inicia levantando los brazos o con el '
              'botón.'),
          value: settings.autoStartOnStill,
          onChanged: (v) =>
              controller.save(settings.copyWith(autoStartOnStill: v)),
        ),
        // Flechas guía durante el intento (el "filtro" de cada paso).
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.navigation_outlined),
          title: const Text('Flechas guía mientras bailo'),
          subtitle: const Text(
              'Marcan a dónde moverte en cada tiempo del paso. Apágalas para '
              'bailar sin ayudas.'),
          value: settings.showCues,
          onChanged: (v) => controller.save(settings.copyWith(showCues: v)),
        ),
        // Tutorial de uso: se muestra solo antes de la primera evaluación;
        // aquí se puede volver a ver cuando se quiera.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: const Text('Ver tutorial de la evaluación'),
          subtitle: const Text(
              'Cómo colocar el teléfono y los gestos para iniciar y '
              'reintentar.'),
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(TutorialPage.route()),
        ),
        // Herramientas de desarrollo: solo en builds debug.
        if (kDebugMode) ...[
          const SizedBox(height: 32),
          const Divider(),
          const _ResetProgressTile(),
        ],
      ],
    );
  }
}

/// Dev TEMPORAL: reinicia a 0 el progreso del usuario en TODOS los pasos
/// (borra sus intentos de HISTORY). Cada ficha de paso tiene el mismo botón
/// para un solo paso.
class _ResetProgressTile extends ConsumerStatefulWidget {
  const _ResetProgressTile();

  @override
  ConsumerState<_ResetProgressTile> createState() => _ResetProgressTileState();
}

class _ResetProgressTileState extends ConsumerState<_ResetProgressTile> {
  bool _busy = false;

  Future<void> _reset() async {
    setState(() => _busy = true);
    try {
      await confirmAndResetProgress(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined,
          color: Theme.of(context).colorScheme.error),
      title: const Text('Reiniciar todo el progreso (dev)'),
      subtitle: const Text('Borra tus intentos de todos los pasos.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _reset,
    );
  }
}
