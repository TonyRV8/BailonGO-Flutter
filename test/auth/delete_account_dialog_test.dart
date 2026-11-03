import 'package:bailongo/features/auth/presentation/providers/auth_providers.dart';
import 'package:bailongo/features/auth/presentation/widgets/delete_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repo;
  bool? result;

  Future<void> open(WidgetTester tester) async {
    repo = FakeAuthRepository();
    result = null;
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await DeleteAccountDialog.show(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextFormField), password);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
  }

  testWidgets('elimina con la contraseña y cierra', (tester) async {
    await open(tester);
    await confirm(tester, 'vieja123');
    expect(repo.deletedWith, ['vieja123']);
    expect(find.byType(DeleteAccountDialog), findsNothing);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin contraseña no intenta borrar', (tester) async {
    await open(tester);
    await confirm(tester, '');
    expect(repo.deletedWith, isEmpty);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
  });

  testWidgets('un error se queda en el diálogo', (tester) async {
    await open(tester);
    repo.failWith = 'La contraseña actual es incorrecta.';
    await confirm(tester, 'mala123');
    expect(find.text('La contraseña actual es incorrecta.'), findsOneWidget);
    expect(find.byType(DeleteAccountDialog), findsOneWidget);
  });

  testWidgets('cancelar no borra nada', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.deletedWith, isEmpty);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
