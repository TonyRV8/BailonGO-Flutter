import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/config/app_constants.dart';
import '../../auth/data/models/app_user_model.dart';
import '../../auth/domain/entities/app_user.dart';

/// Lee y actualiza el perfil del usuario (colección USERS). RF-02.
class ProfileRepository {
  ProfileRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _auth = auth,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

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

  /// Sube la foto de perfil a Storage (`profile_photos/{uid}.jpg`) y guarda
  /// la URL en USERS.fotoUrl (RF-02).
  Future<String> updatePhoto(String uid, File image) async {
    final ref = _storage.ref('profile_photos/$uid.jpg');
    await ref.putFile(
      image,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();
    await _doc(uid).set({'fotoUrl': url}, SetOptions(merge: true));
    await _auth.currentUser?.updatePhotoURL(url);
    return url;
  }
}
