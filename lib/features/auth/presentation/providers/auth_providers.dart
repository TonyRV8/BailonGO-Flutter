import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

// --- Infraestructura Firebase -------------------------------------------------

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

// --- Capa data ---------------------------------------------------------------

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSource(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
);

// --- Estado de sesión --------------------------------------------------------

/// Stream del usuario actual. Lo consume el router para las guardas de ruta.
final authStateProvider = StreamProvider<AppUser>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Acceso sincrónico al usuario actual (puede ser [AppUser.empty]).
final currentUserProvider = Provider<AppUser>((ref) {
  return ref.watch(authStateProvider).value ?? AppUser.empty;
});

// --- Controlador de acciones de auth (login/registro/logout) -----------------

/// Estado de la acción en curso (loading / error) para formularios.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithEmail(email: email, password: password);
    });
  }

  Future<void> register({
    required String email,
    required String password,
    String? nombre,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repo.registerWithEmail(
        email: email,
        password: password,
        nombre: nombre,
      );
    });
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.signOut);
  }
}
