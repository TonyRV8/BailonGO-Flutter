import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/app_user_model.dart';

/// Fuente de datos remota: Firebase Auth (credenciales) + Firestore (perfil).
/// Storage solo se usa al eliminar la cuenta (borra la foto de perfil).
class AuthRemoteDataSource {
  AuthRemoteDataSource({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _auth = auth,
        _firestore = firestore,
        _storage = storage;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  /// Emite el [AppUserModel] del usuario logueado, o `null` si no hay sesión.
  Stream<AppUserModel?> authStateChanges() {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      return _profileFor(user);
    });
  }

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
    final user = await _reauthenticate(currentPassword);
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } catch (e) {
      throw AuthException('No se pudo cambiar la contraseña: $e');
    }
  }

  /// Elimina la cuenta (requisito de Google Play). Confirma la contraseña,
  /// borra los intentos (HISTORY), el perfil (USERS) y la foto, y al final el
  /// usuario de Firebase Auth. Al quedar sin sesión, el router manda al login.
  /// Necesita red: el borrado no puede quedarse pendiente en la cache local.
  Future<void> deleteAccount({required String password}) async {
    final user = await _reauthenticate(password);
    try {
      await _deleteUserData(user.uid).timeout(const Duration(seconds: 30));
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapAuthError(e), code: e.code);
    } on TimeoutException {
      throw AuthException('Sin conexión a la red.');
    } catch (e) {
      throw AuthException('No se pudo eliminar la cuenta: $e');
    }
  }

  Future<void> _deleteUserData(String uid) async {
    final history = await _firestore
        .collection(AppConstants.historyCollection)
        .where('uid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    // Un batch admite hasta 500 operaciones.
    for (var i = 0; i < history.docs.length; i += 400) {
      final batch = _firestore.batch();
      for (final doc in history.docs.skip(i).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _users.doc(uid).delete();
    try {
      await _storage.ref('profile_photos/$uid.jpg').delete();
    } on FirebaseException {
      // Sin foto (object-not-found): no impide borrar la cuenta.
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Firebase exige un inicio de sesión reciente para cambiar la contraseña o
  /// borrar la cuenta: se confirma la contraseña actual antes.
  Future<User> _reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw AuthException('Tu sesión expiró. Inicia sesión de nuevo.');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapReauthError(e), code: e.code);
    }
    return user;
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
