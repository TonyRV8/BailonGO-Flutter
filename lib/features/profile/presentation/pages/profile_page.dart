import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/app_routes.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../catalog/domain/entities/dance_step.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/profile_providers.dart';

/// Perfil + progreso (RF-02, RF-03, RF-04).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(profileProvider);
        ref.invalidate(userBestScoresProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          profile.when(
            loading: () => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
            data: (user) => _Header(user: user),
          ),
          const SizedBox(height: 24),
          Text('Progreso', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const _Progress(),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.user});
  final AppUser user;

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: user.nombre ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Editar nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    controller.dispose();
    if (nombre == null || nombre.isEmpty) return;
    try {
      await ref.read(profileControllerProvider.notifier).updateName(nombre);
      messenger.showSnackBar(const SnackBar(content: Text('Nombre actualizado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Foto de perfil (RF-02): elegir de galería y subir a Storage.
  Future<void> _pickPhoto(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (picked == null) return;
      await ref
          .read(profileControllerProvider.notifier)
          .updatePhoto(File(picked.path));
      messenger.showSnackBar(
          const SnackBar(content: Text('Foto de perfil actualizada.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error al subir: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final initial =
        (user.nombre?.isNotEmpty ?? false) ? user.nombre![0].toUpperCase() : '?';
    final hasPhoto = user.fotoUrl != null && user.fotoUrl!.isNotEmpty;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: hasPhoto ? NetworkImage(user.fotoUrl!) : null,
              child: hasPhoto
                  ? null
                  : Text(initial, style: theme.textTheme.headlineMedium),
            ),
            Material(
              color: theme.colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _pickPhoto(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.camera_alt,
                      size: 16, color: theme.colorScheme.onPrimary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(user.nombre ?? 'Sin nombre', style: theme.textTheme.titleLarge),
        Text(user.email, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Chip(label: Text('Nivel: ${user.nivel}')),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editName(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Salir'),
            ),
          ],
        ),
      ],
    );
  }
}

enum _StepStatus { learned, practicing, notStarted }

class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final scores = ref.watch(userBestScoresProvider);
    // Umbral de "Aprendido" configurable (RN-02, users.settings).
    final threshold = ref.watch(currentSettingsProvider).learnedThreshold;

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (steps) {
        final best = scores.value ?? const <String, double>{};

        _StepStatus statusOf(DanceStep s) {
          final b = best[s.id];
          if (b == null) return _StepStatus.notStarted;
          return b >= threshold
              ? _StepStatus.learned
              : _StepStatus.practicing;
        }

        final learned =
            steps.where((s) => statusOf(s) == _StepStatus.learned).length;
        final practicing =
            steps.where((s) => statusOf(s) == _StepStatus.practicing).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _Stat(
                        label: 'Aprendidos',
                        value: '$learned',
                        color: Colors.green)),
                Expanded(
                    child: _Stat(
                        label: 'En práctica',
                        value: '$practicing',
                        color: Colors.orange)),
                Expanded(child: _Stat(label: 'Total', value: '${steps.length}')),
              ],
            ),
            const SizedBox(height: 12),
            ...steps.map((s) {
              final status = statusOf(s);
              final b = best[s.id];
              return Card(
                child: ListTile(
                  leading: _StatusIcon(status),
                  title: Text(s.nombre),
                  subtitle: Text(_label(status)),
                  trailing: Text(
                    b == null ? '—' : '${b.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  // RF-04: acceso directo a la ficha/evaluación.
                  onTap: () => context.push('${AppRoutes.step}/${s.id}'),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  String _label(_StepStatus s) => switch (s) {
        _StepStatus.learned => 'Aprendido',
        _StepStatus.practicing => 'En práctica',
        _StepStatus.notStarted => 'Sin empezar',
      };
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.status);
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _StepStatus.learned =>
        const Icon(Icons.check_circle, color: Colors.green),
      _StepStatus.practicing =>
        const Icon(Icons.fitness_center, color: Colors.orange),
      _StepStatus.notStarted =>
        Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400),
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.headlineMedium?.copyWith(color: color)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
