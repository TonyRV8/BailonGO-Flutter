import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/settings_repository.dart';
import '../../domain/user_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(firebaseFirestoreProvider)),
);

/// Preferencias del usuario en vivo (defaults si no hay sesión o documento).
final userSettingsProvider = StreamProvider<UserSettings>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return Stream.value(const UserSettings());
  return ref.watch(settingsRepositoryProvider).watch(user.uid);
});

/// Acceso sincrónico con defaults (para páginas que no quieren AsyncValue).
final currentSettingsProvider = Provider<UserSettings>(
  (ref) => ref.watch(userSettingsProvider).value ?? const UserSettings(),
);

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, void>(SettingsController.new);

class SettingsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(UserSettings settings) async {
    final uid = ref.read(currentUserProvider).uid;
    if (uid.isEmpty) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(settingsRepositoryProvider).save(uid, settings),
    );
  }
}
