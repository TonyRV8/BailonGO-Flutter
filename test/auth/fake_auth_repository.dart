import 'package:bailongo/core/error/exceptions.dart';
import 'package:bailongo/features/auth/domain/entities/app_user.dart';
import 'package:bailongo/features/auth/domain/repositories/auth_repository.dart';

/// Repositorio de auth en memoria para pruebas de widgets: registra las
/// llamadas de contraseña y puede fallar con el mensaje que se le indique.
class FakeAuthRepository implements AuthRepository {
  final resetEmails = <String>[];
  final passwordChanges = <(String, String)>[];
  String? failWith;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    if (failWith != null) throw AuthException(failWith!);
    resetEmails.add(email);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (failWith != null) throw AuthException(failWith!);
    passwordChanges.add((currentPassword, newPassword));
  }

  @override
  Stream<AppUser> authStateChanges() => const Stream.empty();

  @override
  AppUser get currentUser => AppUser.empty;

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    String? nombre,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}
