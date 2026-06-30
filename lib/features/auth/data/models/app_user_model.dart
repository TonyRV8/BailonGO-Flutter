import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/app_user.dart';

/// Mapeo entre la entidad de dominio [AppUser] y el documento Firestore
/// de la colección USERS.
class AppUserModel extends AppUser {
  const AppUserModel({
    required super.uid,
    required super.email,
    super.nombre,
    super.fotoUrl,
    super.nivel,
    super.createdAt,
  });

  factory AppUserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return AppUserModel(
      uid: doc.id,
      email: (data['email'] as String?) ?? '',
      nombre: data['nombre'] as String?,
      fotoUrl: data['fotoUrl'] as String?,
      nivel: (data['nivel'] as String?) ?? 'Bronce',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Documento listo para `set()` al crear el usuario. `createdAt` se resuelve
  /// con server timestamp.
  Map<String, dynamic> toFirestoreCreate() => {
        'email': email,
        'nombre': nombre,
        'fotoUrl': fotoUrl,
        'nivel': nivel,
        'createdAt': FieldValue.serverTimestamp(),
        'settings': <String, dynamic>{},
      };
}
