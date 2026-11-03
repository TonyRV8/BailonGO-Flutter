import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_constants.dart';
import '../../../evaluation/presentation/widgets/reset_progress.dart';
import '../../../pose/presentation/pages/laterality_check_page.dart';
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
        // Prueba guiada que dice si hay que activar el interruptor de arriba.
        // Pantalla completa: fuera del shell con el menú inferior.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Comprobar izquierda y derecha'),
          subtitle: const Text(
              'Levanta el brazo derecho y confirma que la app lo reconoce.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(LateralityCheckPage.route()),
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
        // Voz guía (conteo + instrucciones) sobre la música del paso.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: const Text('Voz guía durante la evaluación'),
          subtitle: const Text(
              'Cuenta los tiempos y te dice qué hacer mientras bailas. '
              'Apágala para bailar solo con la música.'),
          value: settings.voiceGuideInEvaluation,
          onChanged: (v) =>
              controller.save(settings.copyWith(voiceGuideInEvaluation: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.ondemand_video_outlined),
          title: const Text('Voz guía en el video del paso'),
          subtitle: const Text(
              'Suena junto a la música del video en la ficha de cada paso.'),
          value: settings.voiceGuideInPreview,
          onChanged: (v) =>
              controller.save(settings.copyWith(voiceGuideInPreview: v)),
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
        const SizedBox(height: 16),
        Text('Acerca de', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Política de privacidad'),
          subtitle: const Text('Qué datos guarda la app y cómo borrarlos.'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse(AppConstants.privacyPolicyUrl),
              mode: LaunchMode.externalApplication),
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
