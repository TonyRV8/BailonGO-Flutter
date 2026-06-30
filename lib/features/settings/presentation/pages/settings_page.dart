import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../catalog/presentation/providers/catalog_providers.dart';

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
