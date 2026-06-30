/// Entidad de dominio del usuario autenticado (colección USERS, doc 5.3.3).
/// Independiente de Firebase: la capa data mapea desde/hacia esta entidad.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    this.nombre,
    this.fotoUrl,
    this.nivel = 'Bronce',
    this.createdAt,
  });

  final String uid;
  final String email;
  final String? nombre;
  final String? fotoUrl;
  final String nivel;
  final DateTime? createdAt;

  /// Usuario vacío/anónimo (sin sesión).
  static const empty = AppUser(uid: '', email: '');

  bool get isEmpty => uid.isEmpty;
  bool get isNotEmpty => uid.isNotEmpty;

  AppUser copyWith({
    String? uid,
    String? email,
    String? nombre,
    String? fotoUrl,
    String? nivel,
    DateTime? createdAt,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      nombre: nombre ?? this.nombre,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      nivel: nivel ?? this.nivel,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.email == email &&
      other.nombre == nombre &&
      other.fotoUrl == fotoUrl &&
      other.nivel == nivel;

  @override
  int get hashCode => Object.hash(uid, email, nombre, fotoUrl, nivel);
}
