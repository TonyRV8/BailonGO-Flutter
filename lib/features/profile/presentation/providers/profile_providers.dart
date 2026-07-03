import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/profile_repository.dart';

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    storage: ref.watch(firebaseStorageProvider),
  ),
);

/// Perfil del usuario (RF-02). Se re-lee tras editar invalidando este provider.
final profileProvider = FutureProvider<AppUser>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return AppUser.empty;
  return ref.watch(profileRepositoryProvider).getProfile(user.uid);
});

/// Controlador de edición de perfil.
final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, void>(ProfileController.new);

class ProfileController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> updateName(String nombre) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentUserProvider).uid;
      if (uid.isEmpty) return;
      await ref.read(profileRepositoryProvider).updateName(uid, nombre);
      ref.invalidate(profileProvider);
    });
  }

  /// Sube la foto de perfil (RF-02) y refresca el perfil.
  Future<void> updatePhoto(File image) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentUserProvider).uid;
      if (uid.isEmpty) return;
      await ref.read(profileRepositoryProvider).updatePhoto(uid, image);
      ref.invalidate(profileProvider);
    });
  }
}
