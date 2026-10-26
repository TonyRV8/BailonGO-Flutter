import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/app_routes.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/widgets/change_password_dialog.dart';
import '../../../catalog/domain/entities/dance_step.dart';
import '../../../catalog/domain/entities/step_stats.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../catalog/presentation/widgets/step_visuals.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/profile_providers.dart';
import '../widgets/edit_name_dialog.dart';

/// Perfil + progreso (RF-02, RF-03, RF-04).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(profileProvider);
        ref.invalidate(userStepStatsProvider);
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
    final messenger = ScaffoldMessenger.of(context);
    final nombre =
        await EditNameDialog.show(context, initial: user.nombre ?? '');
    // Sin cambios no hay nada que guardar (ni que recargar).
    if (nombre == null || nombre.isEmpty || nombre == user.nombre) return;
    try {
      await ref.read(profileControllerProvider.notifier).updateName(nombre);
      messenger
          .showSnackBar(const SnackBar(content: Text('Nombre actualizado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await ChangePasswordDialog.show(context);
    if (changed == true) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')));
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
    final initial = (user.nombre?.isNotEmpty ?? false)
        ? user.nombre![0].toUpperCase()
        : '?';
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
        // Wrap: en pantallas angostas con letra grande los dos botones no
        // caben en una fila y pasan a la siguiente en vez de desbordarse.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editName(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Salir'),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: () => _changePassword(context),
          icon: const Icon(Icons.lock_reset),
          label: const Text('Cambiar contraseña'),
        ),
      ],
    );
  }
}

/// Progreso (RF-03): el paso que conviene seguir practicando y la lista de
/// los 9 con su miniatura, barra y estado. Cada fila lleva a su ficha (RF-04).
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final stats = ref.watch(userStepStatsProvider);
    // Umbral de "Aprendido" configurable (RN-02, users.settings).
    final threshold = ref.watch(currentSettingsProvider).learnedThreshold;

    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (steps) {
        final data = stats.value ?? const <String, StepStats>{};
        StepProgress progressOf(DanceStep s) =>
            StepProgress.of(data[s.id]?.best, threshold);

        final learned =
            steps.where((s) => progressOf(s) == StepProgress.learned).length;
        final practicing =
            steps.where((s) => progressOf(s) == StepProgress.practicing).length;
        // Sólo los pasos del catálogo: HISTORY puede tener intentos de los
        // antiguos pasos de prueba.
        final attempts =
            steps.fold<int>(0, (a, s) => a + (data[s.id]?.attempts ?? 0));
        final next = _nextStep(steps, data, progressOf);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Aprendidos',
                    value: '$learned/${steps.length}',
                    color: StepProgress.learned.color,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'En práctica',
                    value: '$practicing',
                    color: StepProgress.practicing.color,
                  ),
                ),
                Expanded(child: _Stat(label: 'Intentos', value: '$attempts')),
              ],
            ),
            const SizedBox(height: 16),
            if (next != null) ...[
              _ContinueCard(
                step: next,
                stats: data[next.id],
                progress: progressOf(next),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Text(
                  'Todos los pasos',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                _CountBadge('${steps.length}'),
              ],
            ),
            const SizedBox(height: 8),
            for (final s in steps)
              _StepRow(step: s, stats: data[s.id], progress: progressOf(s)),
          ],
        );
      },
    );
  }

  /// Paso a sugerir: el último que practicó sin haberlo aprendido; si no hay,
  /// el primero que aún no empieza; si ya aprendió todos, el último practicado.
  static DanceStep? _nextStep(
    List<DanceStep> steps,
    Map<String, StepStats> data,
    StepProgress Function(DanceStep) progressOf,
  ) {
    DanceStep? latest(Iterable<DanceStep> pool) {
      DanceStep? pick;
      DateTime? at;
      for (final s in pool) {
        final t = data[s.id]?.lastAt;
        if (t != null && (at == null || t.isAfter(at))) {
          pick = s;
          at = t;
        }
      }
      return pick;
    }

    return latest(
            steps.where((s) => progressOf(s) == StepProgress.practicing)) ??
        steps
            .where((s) => progressOf(s) == StepProgress.notStarted)
            .firstOrNull ??
        latest(steps) ??
        steps.firstOrNull;
  }
}

String _attemptsText(int n) => '$n ${n == 1 ? 'intento' : 'intentos'}';

/// Tarjeta grande "Continúa practicando" con la toma del paso de fondo.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.step,
    required this.stats,
    required this.progress,
  });

  final DanceStep step;
  final StepStats? stats;
  final StepProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = stats?.best?.round();
    final n = stats?.attempts ?? 0;
    final (kicker, detail) = switch (progress) {
      StepProgress.practicing => (
          'CONTINÚA PRACTICANDO',
          'Mejor $best % · ${_attemptsText(n)}',
        ),
      StepProgress.notStarted => ('TU SIGUIENTE PASO', stepTagline(step)),
      StepProgress.learned => (
          '¡YA LOS APRENDISTE TODOS!',
          'Repasa el último: mejor $best %',
        ),
    };
    final bg = scheme.surfaceContainerHighest;
    void open() => context.push('${AppRoutes.step}/${step.id}');
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      color: bg,
      child: InkWell(
        onTap: open,
        // Alto mínimo de 180; crece si el texto no cabe (letra grande).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 180),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.62,
                    heightFactor: 1,
                    // Recuadro ancho: se encuadra el torso y la cabeza.
                    child: StepThumbnail(
                      step: step,
                      alignment: const Alignment(0, -0.55),
                    ),
                  ),
                ),
              ),
              // La foto se funde con el fondo para que el texto se lea.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      stops: const [0.38, 0.62, 1],
                      colors: [
                        bg,
                        bg.withValues(alpha: 0.45),
                        bg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kicker,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 200,
                      child: Text(
                        step.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      // El tema estira los botones a todo lo ancho; aquí va
                      // compacto para no tapar la foto.
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: open,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Practicar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de un paso: miniatura vertical, nombre, frase, barra y estado.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.stats,
    required this.progress,
  });

  final DanceStep step;
  final StepStats? stats;
  final StepProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = stats?.best;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('${AppRoutes.step}/${step.id}'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 54,
                    height: 72,
                    child: StepThumbnail(step: step),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        stepTagline(step),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                      const SizedBox(height: 6),
                      if (best != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: best / 100,
                            minHeight: 5,
                            color: progress.color,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        best == null
                            ? 'Sin intentos'
                            : '${best.round()} % · '
                                '${_attemptsText(stats?.attempts ?? 0)}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (progress == StepProgress.learned)
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: progress.color,
                    child: Icon(Icons.check, size: 18, color: progress.onColor),
                  )
                else
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
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
