import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../catalog/data/catalog_seed.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../evaluation/engine/dtw_comparator.dart';
import '../../../evaluation/engine/dtw_result.dart';
import '../../../evaluation/presentation/providers/evaluation_providers.dart';
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
        // Herramientas de desarrollo: solo en builds debug.
        if (kDebugMode) ...[
          const SizedBox(height: 32),
          const Divider(),
          const _SeedCatalogTile(),
          const _UploadReferenceTile(),
          const _ValidateEngineTile(),
          const _ResetTestProgressTile(),
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

/// Dev: extrae la referencia del paso de prueba y la sube a Firestore
/// (REFERENCE_DATA) para que la evaluación cargue al instante.
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
      final steps = kCatalogSeed
          .where((s) => kTestStepIds.contains(s.id))
          .toList(growable: false);
      final n = await ref
          .read(referenceRepositoryProvider)
          .extractAndUploadAll(steps);
      messenger.showSnackBar(
        SnackBar(
            content: Text(
                'Referencia subida para ${steps.length} pasos: $n frames.')),
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
      subtitle:
          const Text('Extrae los pasos de prueba y los guarda en Firestore.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _run,
    );
  }
}

/// Dev: corre el motor sobre los fixtures (good/bad.mov vs ref.mov) y muestra
/// los scores. `good` debe dar alto y `bad` bajo.
class _ValidateEngineTile extends ConsumerStatefulWidget {
  const _ValidateEngineTile();

  @override
  ConsumerState<_ValidateEngineTile> createState() =>
      _ValidateEngineTileState();
}

class _ValidateEngineTileState extends ConsumerState<_ValidateEngineTile> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final proc = ref.read(videoPoseProcessorProvider);
      final refF = await proc.processAsset('assets/fixtures/ref.mov');
      final goodF = await proc.processAsset('assets/fixtures/good.mov');
      final badF = await proc.processAsset('assets/fixtures/bad.mov');
      // Usa los pesos del paso de prueba (tren superior).
      final weights =
          kCatalogSeed.firstWhere((s) => s.id == 'paso_prueba').weights;
      final good = DtwComparator.compare(goodF, refF, weights: weights);
      final bad = DtwComparator.compare(badF, refF, weights: weights);
      if (!mounted) return;
      String worst(DtwResult result) {
        final i = result.worstComponentIndex;
        return (i >= 0 && i < DtwResult.componentNames.length)
            ? DtwResult.componentNames[i]
            : '?';
      }

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Validación del motor'),
          content: SingleChildScrollView(
            child: Text(
              'frames válidos → ref ${refF.length} | good ${goodF.length} | bad ${badF.length}\n\n'
              'GOOD vs ref → total ${good.score}% '
              '(align ${good.alignmentScore}, ritmo ${good.rhythmScore})\n'
              'normCost ${good.normalizedCost.toStringAsFixed(3)} | peor: ${worst(good)}\n\n'
              'BAD vs ref → total ${bad.score}% '
              '(align ${bad.alignmentScore}, ritmo ${bad.rhythmScore})\n'
              'normCost ${bad.normalizedCost.toStringAsFixed(3)} | peor: ${worst(bad)}',
            ),
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
      leading: const Icon(Icons.science_outlined),
      title: const Text('Validar motor (dev)'),
      subtitle: const Text('good/bad.mov vs ref.mov → scores.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _run,
    );
  }
}

/// Dev TEMPORAL: borra del HISTORY los intentos del usuario en los pasos de
/// prueba, para re-testear la sincronización de la mejor marca desde cero.
class _ResetTestProgressTile extends ConsumerStatefulWidget {
  const _ResetTestProgressTile();

  @override
  ConsumerState<_ResetTestProgressTile> createState() =>
      _ResetTestProgressTileState();
}

class _ResetTestProgressTileState
    extends ConsumerState<_ResetTestProgressTile> {
  bool _busy = false;

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar progreso de prueba?'),
        content: const Text(
            'Se eliminarán TODOS tus intentos de los pasos de prueba '
            '(1, 2 y 3). No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = ref.read(currentUserProvider).uid;
      if (uid.isEmpty) return;
      final firestore = ref.read(firebaseFirestoreProvider);
      final snap = await firestore
          .collection(AppConstants.historyCollection)
          .where('uid', isEqualTo: uid)
          .where('pasoId', whereIn: kTestStepIds)
          .get();
      final batch = firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      // Refresca mejores marcas y progreso.
      ref.invalidate(bestScoreProvider);
      ref.invalidate(userBestScoresProvider);
      messenger.showSnackBar(
        SnackBar(
            content: Text('Progreso borrado: ${snap.docs.length} intentos.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error al borrar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined,
          color: Theme.of(context).colorScheme.error),
      title: const Text('Borrar progreso de prueba (dev)'),
      subtitle: const Text('Elimina tus intentos de los pasos de prueba.'),
      trailing: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _reset,
    );
  }
}
