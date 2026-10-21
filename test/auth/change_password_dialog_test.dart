import 'package:bailongo/features/auth/presentation/providers/auth_providers.dart';
import 'package:bailongo/features/auth/presentation/widgets/change_password_dialog.dart';
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
                result = await ChangePasswordDialog.show(context),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String current, String next,
      [String? confirm]) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña actual'), current);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nueva contraseña'), next);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
        confirm ?? next);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
  }

  testWidgets('cambia la contraseña y cierra el diálogo', (tester) async {
    await open(tester);
    await fill(tester, 'vieja123', 'nueva456');
    await save(tester);
    expect(repo.passwordChanges, [('vieja123', 'nueva456')]);
    expect(find.byType(ChangePasswordDialog), findsNothing);
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la confirmación debe coincidir', (tester) async {
    await open(tester);
    await fill(tester, 'vieja123', 'nueva456', 'nueva457');
    await save(tester);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(repo.passwordChanges, isEmpty);
  });

  testWidgets('la nueva debe ser distinta de la actual', (tester) async {
    await open(tester);
    await fill(tester, 'misma123', 'misma123');
    await save(tester);
    expect(find.text('Debe ser distinta de la actual.'), findsOneWidget);
    expect(repo.passwordChanges, isEmpty);
  });

  testWidgets('la nueva debe tener al menos 6 caracteres', (tester) async {
    await open(tester);
    await fill(tester, 'vieja123', 'abc');
    await save(tester);
    expect(find.text('Mínimo 6 caracteres.'), findsWidgets);
    expect(repo.passwordChanges, isEmpty);
  });

  testWidgets('un error se muestra sin cerrar el diálogo', (tester) async {
    await open(tester);
    repo.failWith = 'La contraseña actual es incorrecta.';
    await fill(tester, 'mala1234', 'nueva456');
    await save(tester);
    expect(find.text('La contraseña actual es incorrecta.'), findsOneWidget);
    expect(find.byType(ChangePasswordDialog), findsOneWidget);
    repo.failWith = null;
    await save(tester);
    expect(repo.passwordChanges, [('mala1234', 'nueva456')]);
    expect(result, isTrue);
  });

  testWidgets('cancelar no cambia nada', (tester) async {
    await open(tester);
    await fill(tester, 'vieja123', 'nueva456');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.passwordChanges, isEmpty);
    expect(result, isNot(true));
    expect(tester.takeException(), isNull);
  });
}
