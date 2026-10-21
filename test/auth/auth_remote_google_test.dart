// Fakes mínimos de Firestore: sus clases están selladas para usuarios
// externos, pero aquí solo se implementa lo que usa el datasource.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable

import 'package:bailongo/core/error/exceptions.dart';
import 'package:bailongo/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:bailongo/features/auth/data/datasources/google_id_token_source.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Firestore en memoria (solo lo que usa el datasource) --------------------

class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic>? _data;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data;
}

class _Doc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.id, this._store);
  @override
  final String id;
  final Map<String, Map<String, dynamic>> _store;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          [GetOptions? options]) async =>
      _Snapshot(id, _store[id]);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async =>
      // El servidor resuelve los FieldValue (createdAt): aquí quedan en null.
      _store[id] = {
        for (final e in data.entries)
          e.key: e.value is FieldValue ? null : e.value,
      };
}

class _Users extends Fake implements CollectionReference<Map<String, dynamic>> {
  _Users(this.store);
  final Map<String, Map<String, dynamic>> store;
  int writes = 0;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _CountingDoc(path!, store, this);
}

class _CountingDoc extends _Doc {
  _CountingDoc(super.id, super.store, this._users);
  final _Users _users;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) {
    _users.writes++;
    return super.set(data, options);
  }
}

class _Firestore extends Fake implements FirebaseFirestore {
  final users = _Users({});
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => users;
}

// --- Firebase Auth y Google ---------------------------------------------------

class _UserInfo extends Fake implements UserInfo {
  _UserInfo(this.providerId);
  @override
  final String providerId;
}

class _User extends Fake implements User {
  _User({this.providers = const ['google.com']});
  final List<String> providers;
  @override
  String get uid => 'u1';
  @override
  String? get email => 'ana@gmail.com';
  @override
  String? get displayName => 'Ana Pérez';
  @override
  String? get photoURL => 'https://foto';
  @override
  List<UserInfo> get providerData => [for (final p in providers) _UserInfo(p)];
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User? user;
}

class _Auth extends Fake implements FirebaseAuth {
  final credentials = <String>[];
  FirebaseAuthException? error;
  int signOuts = 0;
  @override
  User? currentUser;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentials.add(
        '${credential.providerId} ${(credential as OAuthCredential).idToken}');
    if (error != null) throw error!;
    return _Credential(currentUser = _User());
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class _Google implements GoogleIdTokenSource {
  String? token = 'id-token';
  AuthException? error;
  int signOuts = 0;

  @override
  Future<String?> pickIdToken() async {
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  late _Auth auth;
  late _Firestore firestore;
  late _Google google;
  late AuthRemoteDataSource source;

  setUp(() {
    auth = _Auth();
    firestore = _Firestore();
    google = _Google();
    source =
        AuthRemoteDataSource(auth: auth, firestore: firestore, google: google);
  });

  test('entra a Firebase con el token de Google y crea el perfil', () async {
    final user = await source.signInWithGoogle();
    expect(auth.credentials, ['google.com id-token']);
    expect(user.uid, 'u1');
    expect(user.nombre, 'Ana Pérez');
    final doc = firestore.users.store['u1']!;
    expect(doc['email'], 'ana@gmail.com');
    expect(doc['nombre'], 'Ana Pérez');
    expect(doc['fotoUrl'], 'https://foto');
    expect(doc['nivel'], 'Bronce');
  });

  test('si el perfil ya existe no lo sobrescribe', () async {
    firestore.users.store['u1'] = {
      'email': 'ana@gmail.com',
      'nombre': 'Anita',
      'nivel': 'Oro',
    };
    final user = await source.signInWithGoogle();
    expect(firestore.users.writes, 0);
    expect(user.nombre, 'Anita');
    expect(user.nivel, 'Oro');
  });

  test('cancelar el selector no toca Firebase', () async {
    google.token = null;
    await expectLater(
        source.signInWithGoogle(),
        throwsA(isA<AuthException>().having(
            (e) => e.code, 'code', AuthRemoteDataSource.googleCanceled)));
    expect(auth.credentials, isEmpty);
  });

  test('un error de Google llega tal cual', () async {
    google.error = AuthException('Inicio con Google no disponible.');
    await expectLater(
        source.signInWithGoogle(),
        throwsA(isA<AuthException>().having(
            (e) => e.message, 'message', 'Inicio con Google no disponible.')));
  });

  test('traduce los errores de Firebase', () async {
    for (final (code, message) in [
      ('user-disabled', 'La cuenta está deshabilitada.'),
      ('network-request-failed', 'Sin conexión a la red.'),
      (
        'account-exists-with-different-credential',
        'Ese correo ya está registrado con contraseña. Inicia sesión con '
            'tu correo y contraseña.'
      ),
    ]) {
      auth.error = FirebaseAuthException(code: code);
      await expectLater(
          source.signInWithGoogle(),
          throwsA(isA<AuthException>()
              .having((e) => e.message, 'message', message)));
    }
  });

  test('cerrar sesión también cierra la de Google', () async {
    await source.signOut();
    expect(auth.signOuts, 1);
    expect(google.signOuts, 1);
  });

  test('cerrar sesión no falla si Google no responde', () async {
    final failing = _FailingGoogle();
    source =
        AuthRemoteDataSource(auth: auth, firestore: firestore, google: failing);
    await source.signOut();
    expect(auth.signOuts, 1);
  });

  test('sabe si la cuenta tiene contraseña', () {
    auth.currentUser = _User(providers: ['google.com']);
    expect(source.currentUserHasPassword, isFalse);
    auth.currentUser = _User(providers: ['google.com', 'password']);
    expect(source.currentUserHasPassword, isTrue);
    auth.currentUser = null;
    expect(source.currentUserHasPassword, isFalse);
  });
}

class _FailingGoogle extends _Google {
  @override
  Future<void> signOut() async => throw Exception('sin Play Services');
}
