import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/app_user_model.dart';
import 'google_id_token_source.dart';

/// Fuente de datos remota: Firebase Auth (credenciales) + Firestore (perfil).
class AuthRemoteDataSource {
  AuthRemoteDataSource({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    GoogleIdTokenSource? google,
  })  : _auth = auth,
        _firestore = firestore,
        _google = google ?? GoogleSignInIdTokenSource();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleIdTokenSource _google;

  /// Código de [AuthException] cuando el usuario cierra el selector de
  /// Google sin elegir cuenta: no es un error que haya que mostrar.
  static const googleCanceled = 'google-canceled';

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  /// Emite el [AppUserModel] del usuario logueado, o `null` si no hay sesión.
  Stream<AppUserModel?> authStateChanges() {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      return _profileFor(user);
    });
  }

  /// La cuenta con sesión puede entrar con contraseña (no solo con Google).
  bool get currentUserHasPassword =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == EmailAuthProvider.PROVIDER_ID) ??
      false;

  AppUserModel? get currentUserOrNull {
    final user = _auth.currentUser;
    if (user == null) return null;
    return AppUserModel(uid: user.uid, email: user.email ?? '');
  }

  Future<AppUserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _profileFor(cred.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo iniciar sesión: $e');
    }
  }

  Future<AppUserModel> registerWithEmail({
    required String email,
    required String password,
    String? nombre,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      if (nombre != null && nombre.isNotEmpty) {
        await user.updateDisplayName(nombre);
      }

      final model = AppUserModel(
        uid: user.uid,
        email: user.email ?? email,
        nombre: nombre,
      );
      // Crea el documento de perfil en USERS.
      await _users.doc(user.uid).set(model.toFirestoreCreate());
      return _profileFor(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo registrar: $e');
    }
  }

  /// Correo de Firebase con el enlace para elegir una contraseña nueva.
  /// Si el correo no tiene cuenta termina igual que si la tuviera, para no
  /// revelar qué correos están registrados.
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.setLanguageCode('es');
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo enviar el correo: $e');
    }
  }

  /// Firebase solo deja cambiar la contraseña con un inicio de sesión
  /// reciente: se confirma la actual (reautenticación) y luego se cambia.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw AuthException('Tu sesión expiró. Inicia sesión de nuevo.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapReauthError(e), code: e.code);
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo cambiar la contraseña: $e');
    }
  }

  /// Selector de cuentas de Google y luego Firebase con su ID token. El
  /// primer ingreso crea el perfil en USERS como el registro; si ya existe
  /// (p. ej. una cuenta de correo con el mismo email) no se toca.
  Future<AppUserModel> signInWithGoogle() async {
    final idToken = await _google.pickIdToken();
    if (idToken == null) {
      throw AuthException('Inicio de sesión cancelado.', code: googleCanceled);
    }
    try {
      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      final user = cred.user!;
      await _ensureProfile(user);
      return _profileFor(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo iniciar sesión con Google: $e');
    }
  }

  Future<void> _ensureProfile(User user) async {
    final doc = _users.doc(user.uid);
    if ((await doc.get()).exists) return;
    await doc.set(AppUserModel(
      uid: user.uid,
      email: user.email ?? '',
      nombre: user.displayName,
      fotoUrl: user.photoURL,
    ).toFirestoreCreate());
  }

  /// Cierra también la sesión de Google, para que el próximo ingreso deje
  /// elegir cuenta. Si Google falla (sin Play Services) igual se sale.
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Lee el perfil de Firestore; si aún no existe (p.ej. registro a medias),
  /// regresa un modelo básico con los datos de Auth.
  Future<AppUserModel> _profileFor(User user) async {
    try {
      final doc = await _users.doc(user.uid).get();
      if (doc.exists) return AppUserModel.fromFirestore(doc);
    } catch (_) {
      // Sin red: degradar a datos de Auth (offline-first, fase 7).
    }
    return AppUserModel(
      uid: user.uid,
      email: user.email ?? '',
      nombre: user.displayName,
      fotoUrl: user.photoURL,
    );
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo no es válido.';
      case 'user-disabled':
        return 'La cuenta está deshabilitada.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak-password':
        return 'La contraseña es demasiado débil (mín. 6 caracteres).';
      case 'network-request-failed':
        return 'Sin conexión a la red.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      case 'account-exists-with-different-credential':
        return 'Ese correo ya está registrado con contraseña. Inicia sesión '
            'con tu correo y contraseña.';
      case 'requires-recent-login':
        return 'Por seguridad, inicia sesión de nuevo e inténtalo otra vez.';
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }

  /// Al confirmar la contraseña actual, "credencial inválida" significa que
  /// la contraseña escrita no es la actual (no que el correo sea incorrecto).
  String _mapReauthError(FirebaseAuthException e) => switch (e.code) {
        'wrong-password' ||
        'invalid-credential' ||
        'invalid-login-credentials' =>
          'La contraseña actual es incorrecta.',
        _ => _mapAuthError(e),
      };
}
