import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/app_constants.dart';
import '../../auth/data/models/app_user_model.dart';
import '../../auth/domain/entities/app_user.dart';

/// Lee y actualiza el perfil del usuario (colección USERS). RF-02.
class ProfileRepository {
  ProfileRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection(AppConstants.usersCollection).doc(uid);

  Future<AppUser> getProfile(String uid) async {
    final doc = await _doc(uid).get();
    if (doc.exists) return AppUserModel.fromFirestore(doc);
    final u = _auth.currentUser;
    return AppUser(
      uid: uid,
      email: u?.email ?? '',
      nombre: u?.displayName,
      fotoUrl: u?.photoURL,
    );
  }

  Future<void> updateName(String uid, String nombre) async {
    await _doc(uid).set({'nombre': nombre}, SetOptions(merge: true));
    await _auth.currentUser?.updateDisplayName(nombre);
  }
}
