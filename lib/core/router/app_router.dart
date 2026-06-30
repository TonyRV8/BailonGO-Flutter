import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/catalog/presentation/pages/catalog_page.dart';
import '../../features/catalog/presentation/pages/step_detail_page.dart';
import '../../features/evaluation/presentation/pages/evaluation_page.dart';
import '../../features/pose/presentation/pages/pose_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import 'app_routes.dart';
import 'home_shell.dart';
import 'splash_page.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Router de la app con guardas basadas en el estado de sesión.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Notifica al router cuando cambia el estado de auth, sin recrear el router.
  final refresh = ValueNotifier<AsyncValue<AppUser>>(const AsyncLoading());
  ref.listen<AsyncValue<AppUser>>(
    authStateProvider,
    (_, next) => refresh.value = next,
    fireImmediately: true,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = refresh.value;
      final loc = state.matchedLocation;

      // Mientras se resuelve la sesión inicial, permanecer en el splash.
      if (authState.isLoading || !authState.hasValue) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final loggedIn = authState.value!.isNotEmpty;
      final onAuthPage =
          loc == AppRoutes.login || loc == AppRoutes.register;
      final onSplash = loc == AppRoutes.splash;

      if (!loggedIn) return onAuthPage ? null : AppRoutes.login;
      if (loggedIn && (onAuthPage || onSplash)) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, __) => const RegisterPage(),
      ),
      // Shell con Drawer persistente (RF-01).
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.catalog,
            builder: (_, __) => const CatalogPage(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, __) => const ProfilePage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, __) => const SettingsPage(),
          ),
        ],
      ),
      // Ficha de paso (RF-06), pantalla propia sobre el shell.
      GoRoute(
        path: '${AppRoutes.step}/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            StepDetailPage(stepId: state.pathParameters['id']!),
      ),
      // Cámara / pose (RF-09, Fase 3).
      GoRoute(
        path: '${AppRoutes.pose}/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            PosePage(stepId: state.pathParameters['id']!),
      ),
      // Evaluación end-to-end (Fase 5).
      GoRoute(
        path: '${AppRoutes.evaluate}/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            EvaluationPage(stepId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});
