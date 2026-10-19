import 'package:bailongo/features/tutorial/presentation/pages/tutorial_page.dart';
import 'package:bailongo/features/tutorial/presentation/widgets/mock_camera.dart';
import 'package:bailongo/features/tutorial/presentation/widgets/phone_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// En teléfonos chicos o con letra grande del sistema, el texto no debe
/// comerse la animación ni empujar los botones fuera de la pantalla (pasó en
/// un teléfono real: solo se veían el texto y las barras).
void main() {
  const cases = [
    (Size(320, 640), 1.0),
    (Size(360, 780), 2.0),
    (Size(412, 915), 1.3),
  ];
  for (final (size, scale) in cases) {
    testWidgets('se ve completo en ${size.width}x${size.height}, letra x$scale',
        (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 120, bottom: 72);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const MaterialApp(home: TutorialPage()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 1500));
        final art = tester
            .getRect(i < 2 ? find.byType(PhoneScene) : find.byType(MockCamera));
        expect(art.height, greaterThan(180), reason: 'escena ${i + 1}: $art');
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.top >= 0 && button.bottom <= size.height, isTrue,
            reason: 'botón fuera de pantalla: $button');
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
      }
    });
  }
}
