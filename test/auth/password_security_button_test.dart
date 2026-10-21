import 'package:bailongo/features/auth/presentation/providers/auth_providers.dart';
import 'package:bailongo/features/auth/presentation/widgets/change_password_dialog.dart';
import 'package:bailongo/features/auth/presentation/widgets/password_security_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: Scaffold(body: PasswordSecurityButton(email: 'ana@gmail.com')),
        ),
      ));

  setUp(() => repo = FakeAuthRepository());

  testWidgets('con contraseña abre el diálogo para cambiarla', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordDialog), findsOneWidget);
  });

  testWidgets('cuenta solo de Google: envía correo para crear contraseña',
      (tester) async {
    repo.hasPassword = false;
    await pump(tester);
    expect(find.text('Cambiar contraseña'), findsNothing);
    await tester.tap(find.text('Crear contraseña'));
    await tester.pumpAndSettle();
    expect(repo.resetEmails, ['ana@gmail.com']);
    expect(find.textContaining('Te enviamos un correo a ana@gmail.com'),
        findsOneWidget);
  });

  testWidgets('si el correo falla lo dice', (tester) async {
    repo
      ..hasPassword = false
      ..failWith = 'Sin conexión a la red.';
    await pump(tester);
    await tester.tap(find.text('Crear contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión a la red.'), findsOneWidget);
  });
}
