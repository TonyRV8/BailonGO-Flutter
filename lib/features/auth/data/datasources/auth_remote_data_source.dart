import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/app_user_model.dart';

/// Fuente de datos remota: Firebase Auth (credenciales) + Firestore (perfil).
class AuthRemoteDataSource {
  AuthRemoteDataSource({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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

  Future<void> signOut() => _auth.signOut();

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
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }
}
