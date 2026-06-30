import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Stream<AppUser> authStateChanges() =>
      _remote.authStateChanges().map((m) => m ?? AppUser.empty);

  @override
  AppUser get currentUser => _remote.currentUserOrNull ?? AppUser.empty;

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _remote.signInWithEmail(email: email, password: password);

  @override
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    String? nombre,
  }) =>
      _remote.registerWithEmail(
        email: email,
        password: password,
        nombre: nombre,
      );

  @override
  Future<void> signOut() => _remote.signOut();
}
