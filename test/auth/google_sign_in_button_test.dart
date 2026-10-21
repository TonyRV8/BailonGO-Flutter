import 'package:bailongo/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:bailongo/features/auth/presentation/pages/login_page.dart';
import 'package:bailongo/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;

  Future<void> tapGoogle(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: LoginPage()),
    ));
    // El controlador de auth arranca en carga un instante (build async).
    await tester.pump();
    await tester.ensureVisible(find.text('Continuar con Google'));
    await tester.tap(find.text('Continuar con Google'));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = FakeAuthRepository());

  testWidgets('el login ofrece entrar con Google', (tester) async {
    await tapGoogle(tester);
    expect(repo.googleSignIns, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('cancelar el selector no muestra error', (tester) async {
    repo
      ..failWith = 'Inicio de sesión cancelado.'
      ..failCode = AuthRemoteDataSource.googleCanceled;
    await tapGoogle(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('un error real se muestra', (tester) async {
    repo.failWith = 'Sin conexión a la red.';
    await tapGoogle(tester);
    expect(find.text('Sin conexión a la red.'), findsOneWidget);
  });
}
