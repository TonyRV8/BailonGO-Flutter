import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../catalog/data/catalog_seed.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../evaluation/engine/dtw_comparator.dart';
import '../../../evaluation/engine/dtw_result.dart';
import '../../../evaluation/presentation/providers/evaluation_providers.dart';

/// Configuración (RF-01). Por ahora solo incluye herramientas de desarrollo.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 8),
        Text(
          'Preferencias, modelo de pose y cuenta.\nDisponible en fases posteriores.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // Herramientas de desarrollo: solo en builds debug.
        if (kDebugMode) ...[
          const SizedBox(height: 32),
          const Divider(),
          const _SeedCatalogTile(),
          const _UploadReferenceTile(),
          const _ValidateEngineTile(),
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
        const SnackBar(content: Text('Catálogo sembrado (9 pasos).')),
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
      subtitle: const Text('Escribe los 9 pasos en Firestore.'),
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
      final step = kCatalogSeed.firstWhere((s) => s.id == 'paso_prueba');
      final n =
          await ref.read(referenceRepositoryProvider).extractAndUpload(step);
      messenger.showSnackBar(
        SnackBar(content: Text('Referencia subida: $n frames.')),
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
      subtitle: const Text('Extrae paso_prueba y la guarda en Firestore.'),
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
