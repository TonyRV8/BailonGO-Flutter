import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_constants.dart';
import '../domain/user_settings.dart';

/// Lee y persiste `users/{uid}.settings` (doc 5.3.3). La lectura es un stream
/// del documento, así los cambios se reflejan al instante y sirven desde la
/// cache offline.
class SettingsRepository {
  SettingsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection(AppConstants.usersCollection).doc(uid);

  Stream<UserSettings> watch(String uid) {
    return _doc(uid).snapshots().map((snap) => UserSettings.fromMap(
        (snap.data()?['settings'] as Map<String, dynamic>?)));
  }

  Future<void> save(String uid, UserSettings settings) {
    return _doc(uid)
        .set({'settings': settings.toMap()}, SetOptions(merge: true));
  }
}
