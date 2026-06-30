import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';

/// Perfil básico (RF-02). Editar perfil y progreso (RF-03/04) llegan en la
/// FASE 6; aquí solo se muestran los datos de sesión.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: scheme.primaryContainer,
            backgroundImage: (user.fotoUrl != null && user.fotoUrl!.isNotEmpty)
                ? NetworkImage(user.fotoUrl!)
                : null,
            child: (user.fotoUrl == null || user.fotoUrl!.isEmpty)
                ? Text(
                    (user.nombre ?? user.email).isNotEmpty
                        ? (user.nombre ?? user.email)[0].toUpperCase()
                        : '?',
                    style: Theme.of(context).textTheme.displaySmall,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 24),
        _InfoTile(
          icon: Icons.person_outline,
          label: 'Nombre',
          value: user.nombre ?? '—',
        ),
        _InfoTile(
          icon: Icons.email_outlined,
          label: 'Correo',
          value: user.email.isEmpty ? '—' : user.email,
        ),
        _InfoTile(
          icon: Icons.workspace_premium_outlined,
          label: 'Nivel',
          value: user.nivel,
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Editar perfil y progreso disponibles en la Fase 6.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      contentPadding: EdgeInsets.zero,
    );
  }
}
