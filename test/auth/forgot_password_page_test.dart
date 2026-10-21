import 'package:bailongo/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:bailongo/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;

  Future<void> pump(WidgetTester tester, {String initialEmail = ''}) async {
    repo = FakeAuthRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: ForgotPasswordPage(initialEmail: initialEmail)),
    ));
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
  }

  testWidgets('un correo no válido no envía nada', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'ana@');
    await send(tester);
    expect(find.text('Correo no válido.'), findsOneWidget);
    expect(repo.resetEmails, isEmpty);
  });

  testWidgets('envía el enlace al correo sin espacios y lo confirma',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), '  ana@mail.com ');
    await send(tester);
    expect(repo.resetEmails, ['ana@mail.com']);
    // Mismo mensaje exista o no la cuenta: no revela qué correos existen.
    expect(find.textContaining('Si existe una cuenta con ana@mail.com'),
        findsOneWidget);
  });

  testWidgets('trae el correo escrito en el login', (tester) async {
    await pump(tester, initialEmail: 'beto@mail.com');
    await send(tester);
    expect(repo.resetEmails, ['beto@mail.com']);
  });

  testWidgets('muestra el error y permite reintentar', (tester) async {
    await pump(tester, initialEmail: 'ana@mail.com');
    repo.failWith = 'Sin conexión a la red.';
    await send(tester);
    expect(find.text('Sin conexión a la red.'), findsOneWidget);
    repo.failWith = null;
    await send(tester);
    expect(repo.resetEmails, ['ana@mail.com']);
  });
}
