import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_constants.dart';
import '../../../catalog/data/catalog_seed.dart';
import '../../../catalog/domain/step_weights.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../evaluation/engine/dtw_comparator.dart';
import '../../../evaluation/engine/dtw_result.dart';
import '../../../evaluation/engine/step_params.dart';
import '../../../evaluation/presentation/providers/evaluation_providers.dart';
import '../../../evaluation/presentation/widgets/reset_progress.dart';
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
        // Herramientas de desarrollo: solo en builds debug.
        if (kDebugMode) ...[
          const SizedBox(height: 32),
          const Divider(),
          const _SeedCatalogTile(),
          const _UploadReferenceTile(),
          const _CalibrateEngineTile(),
          const _ResetProgressTile(),
        ],
      ],
    );
  }
}

/// Botón dev para sembrar los 9 pasos en Firestore (CATALOG). Requiere que la
/// regla de escritura de `catalog` esté temporalmente abierta.
class _SeedCatalogTile extends ConsumerStatefulWidget {
  const _SeedCatalogTile();

  @override
  ConsumerState<_SeedCatalogTile> createState() => _SeedCatalogTileState();
}

class _SeedCatalogTileState extends ConsumerState<_SeedCatalogTile> {
  bool _busy = false;

  Future<void> _seed() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(catalogRepositoryProvider).seedCatalog();
      ref.invalidate(catalogProvider);
      messenger.showSnackBar(
        SnackBar(
            content: Text('Catálogo sembrado (${kCatalogSeed.length} pasos).')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al sembrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_upload_outlined),
      title: const Text('Sembrar catálogo (dev)'),
      subtitle: Text('Escribe los ${kCatalogSeed.length} pasos en Firestore.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _seed,
    );
  }
}

/// Dev: extrae los landmarks de los videos ideales de los 9 pasos reales y los
/// sube a Firestore (REFERENCE_DATA) para que la evaluación cargue al instante.
/// Requiere abrir temporalmente la escritura de `reference_data` en las reglas
/// (implementar_pasos.txt §6.2).
class _UploadReferenceTile extends ConsumerStatefulWidget {
  const _UploadReferenceTile();

  @override
  ConsumerState<_UploadReferenceTile> createState() =>
      _UploadReferenceTileState();
}

class _UploadReferenceTileState extends ConsumerState<_UploadReferenceTile> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final steps = kRealSteps.where((s) => s.hasVideo).toList(growable: false);
      final byStep = await ref
          .read(referenceRepositoryProvider)
          .extractAndUploadAll(steps);
      if (!mounted) return;
      // Verificación de implementar_pasos.txt §3: frameCount debe acercarse a
      // duracion_ms / 33. Muy por debajo = se perdieron fotogramas por falta de
      // visibilidad del tren inferior y la ventana de captura se desincroniza.
      final lines = steps.map((s) {
        final got = byStep[s.id] ?? 0;
        final expected = (s.duracionCicloSeg * 1000 / 33).round();
        final pct = expected > 0 ? got * 100 ~/ expected : 0;
        return '${pct >= 90 ? "OK " : "!! "}${s.id}: $got/$expected ($pct%)';
      }).join('\n');
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Referencia subida'),
          content: SingleChildScrollView(
            child: Text('fotogramas válidos / esperados\n\n$lines'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.upload_file_outlined),
      title: const Text('Subir referencia (dev)'),
      subtitle: Text(
          'Extrae los ${kRealSteps.length} pasos reales y los guarda en '
          'Firestore.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _run,
    );
  }
}

/// Dev: banco de calibración (implementar_pasos.txt §7.1).
///
/// Para cada paso real compara la toma ideal contra sí misma y la toma regular
/// (la que la experta puntúa 4-6/10) contra la ideal. Objetivos:
///   ideal vs ideal    → 95-100 %  (control: debe ser trivialmente alto)
///   regular vs ideal  → 40-60 %   (etiqueta de la experta)
/// La tabla resultante se copia al portapapeles para pegarla en la memoria.
class _CalibrateEngineTile extends ConsumerStatefulWidget {
  const _CalibrateEngineTile();

  @override
  ConsumerState<_CalibrateEngineTile> createState() =>
      _CalibrateEngineTileState();
}

class _CalibrateEngineTileState extends ConsumerState<_CalibrateEngineTile> {
  bool _busy = false;
  String _progress = '';

  static String _worst(DtwResult r) {
    final i = r.worstComponentIndex;
    return (i >= 0 && i < DtwResult.componentNames.length)
        ? DtwResult.componentNames[i]
        : '?';
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _progress = '';
    });
    final messenger = ScaffoldMessenger.of(context);
    final proc = ref.read(videoPoseProcessorProvider);
    final buffer = StringBuffer()
      ..writeln('BANCO DE CALIBRACIÓN — ${DateTime.now()}')
      ..writeln('objetivo: ideal 95-100 % | regular ~50 %')
      ..writeln('');

    final steps = kRealSteps.where((s) => s.hasVideo).toList(growable: false);
    try {
      for (final step in steps) {
        if (!mounted) return;
        setState(() => _progress = step.id);
        final idealF = await proc.processAsset(step.mediaUrl!);
        final regF = await proc.processAsset(regularFixtureFor(step.id));
        if (idealF.isEmpty || regF.isEmpty) {
          buffer.writeln('${step.id}: SIN FOTOGRAMAS VÁLIDOS '
              '(ideal ${idealF.length}, regular ${regF.length})');
          continue;
        }
        // Mismos pesos y parámetros que la evaluación real.
        final weights = kStepWeights[step.id] ?? step.weights;
        final params = paramsFor(step.id);
        final self = DtwComparator.compare(idealF, idealF,
            weights: weights, params: params);
        final reg = DtwComparator.compare(regF, idealF,
            weights: weights, params: params);
        buffer
          ..writeln(step.id)
          ..writeln('  fotogramas   ideal ${idealF.length} | regular ${regF.length}')
          ..writeln('  ideal-vs-ideal   ${self.score} %')
          ..writeln('  regular-vs-ideal ${reg.score} % '
              '(align ${reg.alignmentScore}, ritmo ${reg.rhythmScore})')
          ..writeln('  costeRel ${reg.relativeCost.toStringAsFixed(2)} '
              '| cobertura ${reg.coverage.toStringAsFixed(2)}')
          ..writeln('  normCost ${reg.normalizedCost.toStringAsFixed(3)} '
              '| peor: ${_worst(reg)}')
          ..writeln('');
      }
      final report = buffer.toString();
      await Clipboard.setData(ClipboardData(text: report));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Banco de calibración'),
          content: SingleChildScrollView(
            child: SelectableText(report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK (copiado)')),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.science_outlined),
      title: const Text('Calibrar motor (dev)'),
      subtitle: Text(_busy
          ? 'Procesando $_progress…'
          : 'Tomas ideales vs regulares de los ${kRealSteps.length} pasos.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _run,
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
