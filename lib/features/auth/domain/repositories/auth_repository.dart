import '../entities/app_user.dart';

/// Contrato de autenticación (capa dominio). La implementación vive en
/// features/auth/data y usa Firebase Auth + Firestore.
abstract interface class AuthRepository {
  /// Stream del usuario actual. Emite [AppUser.empty] cuando no hay sesión.
  Stream<AppUser> authStateChanges();

  /// Usuario actual sincrónico (o [AppUser.empty]).
  AppUser get currentUser;

  /// Inicia sesión con email/contraseña.
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  /// Inicia sesión con una cuenta de Google (crea el perfil la primera vez).
  /// Si el usuario cierra el selector lanza una AuthException con código
  /// `google-canceled`.
  Future<AppUser> signInWithGoogle();

  /// La cuenta con sesión tiene contraseña (las de solo Google no).
  bool get hasPasswordSignIn;

  /// Registra un usuario nuevo y crea su documento en USERS.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    String? nombre,
  });

  /// Envía el correo para restablecer la contraseña olvidada. No revela si
  /// el correo tiene cuenta: termina igual en ambos casos.
  Future<void> sendPasswordResetEmail({required String email});

  /// Cambia la contraseña del usuario con sesión, confirmando antes la actual.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Cierra la sesión.
  Future<void> signOut();
}
