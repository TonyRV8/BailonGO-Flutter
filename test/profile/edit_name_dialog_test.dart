import 'package:bailongo/features/profile/presentation/widgets/edit_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El diálogo se cerraba con la pantalla roja "_dependents.isEmpty": el
/// controlador del texto se liberaba mientras el diálogo aún hacía su
/// animación de salida. Se recorren todas las formas de cerrarlo.
void main() {
  Future<String?> close(
      WidgetTester tester, Future<void> Function() action) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await EditNameDialog.show(context, initial: 'Ana');
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Editar nombre'), findsOneWidget);
    await action();
    // Toda la animación de salida: aquí reventaba.
    await tester.pumpAndSettle();
    expect(find.text('Editar nombre'), findsNothing);
    expect(tester.takeException(), isNull);
    return result;
  }

  testWidgets('guardar con nombre nuevo', (tester) async {
    final r = await close(tester, () async {
      await tester.enterText(find.byType(TextField), '  Beto ');
      await tester.tap(find.text('Guardar'));
    });
    expect(r, 'Beto');
  });

  testWidgets('guardar sin cambiar nada', (tester) async {
    final r = await close(tester, () => tester.tap(find.text('Guardar')));
    expect(r, 'Ana');
  });

  testWidgets('cancelar', (tester) async {
    final r = await close(tester, () => tester.tap(find.text('Cancelar')));
    expect(r, isNull);
  });

  testWidgets('tocar fuera del recuadro', (tester) async {
    final r = await close(tester, () => tester.tapAt(const Offset(5, 5)));
    expect(r, isNull);
  });

  testWidgets('Enter en el teclado guarda', (tester) async {
    final r = await close(tester, () async {
      await tester.enterText(find.byType(TextField), 'Caro');
      await tester.testTextInput.receiveAction(TextInputAction.done);
    });
    expect(r, 'Caro');
  });
}
