import 'package:bailongo/features/evaluation/domain/evaluation_feedback.dart';
import 'package:bailongo/features/evaluation/engine/dtw_result.dart';
import 'package:bailongo/features/evaluation/presentation/widgets/results_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// En un iPhone angosto "Reintentar" y "Siguiente" se partían en dos renglones.
void main() {
  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0), (390.0, 1.3)]) {
    testWidgets('botones del reporte en un renglón a $width px (letra $scale)',
        (tester) async {
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      const result = DtwResult.empty;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ResultsSheet(
                result: result,
                feedback: buildFeedback(result),
                hasNext: true,
                canGestureRetry: true,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final label in ['Salir', 'Reintentar', 'Siguiente']) {
        final text = find.text(label);
        expect(text, findsOneWidget);
        final style = tester.widget<Text>(text).style ??
            DefaultTextStyle.of(tester.element(text)).style;
        final box = tester.renderObject<RenderBox>(text);
        final lineHeight =
            (style.fontSize ?? 14) * (style.height ?? 1.43) * scale;
        expect(box.size.height, lessThan(lineHeight * 1.6),
            reason: '"$label" no debe partirse en dos renglones');
      }
    });
  }
}
