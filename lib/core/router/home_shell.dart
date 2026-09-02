import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/profile/presentation/providers/profile_providers.dart';
import 'app_routes.dart';

/// Scaffold con Drawer persistente (RF-01): Catálogo, Perfil, Configuración.
class HomeShell extends ConsumerWidget {
  const HomeShell({
    required this.child,
    required this.location,
    super.key,
  });

  final Widget child;
  final String location;

  static const _items = [
    _NavItem(AppRoutes.catalog, 'Catálogo', Icons.library_music_outlined),
    _NavItem(AppRoutes.profile, 'Perfil', Icons.person_outline),
    _NavItem(AppRoutes.settings, 'Configuración', Icons.settings_outlined),
  ];

  int get _selectedIndex {
    final i = _items.indexWhere((e) => location.startsWith(e.path));
    return i < 0 ? 0 : i;
  }

  String get _title => _items[_selectedIndex].label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Perfil de Firestore (se invalida al editar nombre/foto → el drawer se
    // refresca al instante). Mientras carga, cae al usuario de auth.
    final AppUser user =
        ref.watch(profileProvider).value ?? ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          Navigator.of(context).pop(); // cierra el drawer
          context.go(_items[i].path);
        },
        children: [
          _DrawerHeader(
            nombre: user.nombre ?? 'Bailarín',
            email: user.email,
            fotoUrl: user.fotoUrl,
          ),
          for (final item in _items)
            NavigationDrawerDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            ),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
      body: child,
      // Menú inferior persistente (RF-01), espejo del drawer.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => context.go(_items[i].path),
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.nombre,
    required this.email,
    this.fotoUrl,
  });

  final String nombre;
  final String email;
  final String? fotoUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 56, 16, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primaryContainer,
            backgroundImage:
                (fotoUrl != null && fotoUrl!.isNotEmpty) ? NetworkImage(fotoUrl!) : null,
            child: (fotoUrl == null || fotoUrl!.isEmpty)
                ? Text(
                    nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nombre,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
                Text(email,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}
