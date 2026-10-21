import 'package:bailongo/core/error/exceptions.dart';
import 'package:bailongo/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _FakeUserCredential extends Fake implements UserCredential {}

class _FakeUser extends Fake implements User {
  _FakeUser(this.email);

  @override
  final String? email;
  final calls = <String>[];
  FirebaseAuthException? reauthError;
  FirebaseAuthException? updateError;

  @override
  Future<UserCredential> reauthenticateWithCredential(
      AuthCredential credential) async {
    final c = credential as EmailAuthCredential;
    calls.add('reauth ${c.email} ${c.password}');
    if (reauthError != null) throw reauthError!;
    return _FakeUserCredential();
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('update $newPassword');
    if (updateError != null) throw updateError!;
  }
}

class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser;
  final resets = <String>[];
  String? language;
  FirebaseAuthException? resetError;

  @override
  Future<void> setLanguageCode(String? languageCode) async =>
      language = languageCode;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (resetError != null) throw resetError!;
    resets.add(email);
  }
}

void main() {
  late _FakeAuth auth;
  late AuthRemoteDataSource source;

  setUp(() {
    auth = _FakeAuth();
    source = AuthRemoteDataSource(auth: auth, firestore: _FakeFirestore());
  });

  Matcher authError(String message) =>
      isA<AuthException>().having((e) => e.message, 'message', message);

  group('recuperar contraseña', () {
    test('envía el correo en español', () async {
      await source.sendPasswordResetEmail(email: 'ana@mail.com');
      expect(auth.resets, ['ana@mail.com']);
      expect(auth.language, 'es');
    });

    test('un correo sin cuenta no se delata', () async {
      auth.resetError = FirebaseAuthException(code: 'user-not-found');
      await expectLater(
          source.sendPasswordResetEmail(email: 'nadie@mail.com'), completes);
    });

    test('traduce los errores', () async {
      for (final (code, message) in [
        ('invalid-email', 'El correo no es válido.'),
        ('too-many-requests', 'Demasiados intentos. Espera unos minutos.'),
        ('network-request-failed', 'Sin conexión a la red.'),
      ]) {
        auth.resetError = FirebaseAuthException(code: code);
        await expectLater(
            source.sendPasswordResetEmail(email: 'ana@mail.com'),
            throwsA(authError(message)));
      }
    });
  });

  group('cambiar contraseña', () {
    late _FakeUser user;

    setUp(() => auth.currentUser = user = _FakeUser('ana@mail.com'));

    test('reautentica con la actual y luego cambia', () async {
      await source.changePassword(
          currentPassword: 'vieja123', newPassword: 'nueva456');
      expect(user.calls, ['reauth ana@mail.com vieja123', 'update nueva456']);
    });

    test('contraseña actual incorrecta no intenta cambiar', () async {
      for (final code in ['wrong-password', 'invalid-credential']) {
        user
          ..calls.clear()
          ..reauthError = FirebaseAuthException(code: code);
        await expectLater(
            source.changePassword(
                currentPassword: 'mala', newPassword: 'nueva456'),
            throwsA(authError('La contraseña actual es incorrecta.')));
        expect(user.calls, hasLength(1));
      }
    });

    test('contraseña nueva débil', () async {
      user.updateError = FirebaseAuthException(code: 'weak-password');
      await expectLater(
          source.changePassword(
              currentPassword: 'vieja123', newPassword: 'nueva456'),
          throwsA(authError(
              'La contraseña es demasiado débil (mín. 6 caracteres).')));
    });

    test('sin sesión pide volver a entrar', () async {
      auth.currentUser = null;
      await expectLater(
          source.changePassword(
              currentPassword: 'vieja123', newPassword: 'nueva456'),
          throwsA(authError('Tu sesión expiró. Inicia sesión de nuevo.')));
    });
  });
}
