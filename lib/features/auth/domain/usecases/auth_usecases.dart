import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

/// Casos de uso de autenticación. Envuelven el repositorio para mantener la
/// capa presentación desacoplada de la implementación de datos.

class SignInWithEmail {
  const SignInWithEmail(this._repo);
  final AuthRepository _repo;

  Future<AppUser> call({required String email, required String password}) =>
      _repo.signInWithEmail(email: email, password: password);
}

class RegisterWithEmail {
  const RegisterWithEmail(this._repo);
  final AuthRepository _repo;

  Future<AppUser> call({
    required String email,
    required String password,
    String? nombre,
  }) =>
      _repo.registerWithEmail(
        email: email,
        password: password,
        nombre: nombre,
      );
}

class SignOut {
  const SignOut(this._repo);
  final AuthRepository _repo;

  Future<void> call() => _repo.signOut();
}

class WatchAuthState {
  const WatchAuthState(this._repo);
  final AuthRepository _repo;

  Stream<AppUser> call() => _repo.authStateChanges();
}
