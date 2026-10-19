import 'package:bailongo/features/tutorial/presentation/pages/tutorial_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'el tutorial recorre sus 5 escenas solo y termina con "¡A bailar!"',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context)
                .push(TutorialPage.route(beforeEvaluation: true));
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Paso 1 de 5'), findsOneWidget);
    // Avanza solo: cada escena dura entre 5 y 7 s.
    for (var i = 2; i <= 5; i++) {
      for (var k = 0; k < 75; k++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Paso $i de 5'), findsOneWidget);
    }
    // La última escena se repite hasta que el usuario sigue.
    for (var k = 0; k < 80; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Paso 5 de 5'), findsOneWidget);

    await tester.tap(find.text('¡A bailar!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isTrue);
  });

  testWidgets('Atrás y Siguiente navegan entre escenas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TutorialPage()));
    await tester.pump();
    await tester.tap(find.text('Siguiente'));
    await tester.pump();
    expect(find.text('Paso 2 de 5'), findsOneWidget);
    await tester.tap(find.text('Atrás'));
    await tester.pump();
    expect(find.text('Paso 1 de 5'), findsOneWidget);
  });
}
