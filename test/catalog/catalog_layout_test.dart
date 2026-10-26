import 'dart:typed_data';

import 'package:bailongo/core/theme/app_theme.dart';
import 'package:bailongo/features/auth/domain/entities/app_user.dart';
import 'package:bailongo/features/catalog/data/catalog_seed.dart';
import 'package:bailongo/features/catalog/domain/entities/step_stats.dart';
import 'package:bailongo/features/catalog/presentation/pages/catalog_page.dart';
import 'package:bailongo/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:bailongo/features/profile/presentation/pages/profile_page.dart';
import 'package:bailongo/features/profile/presentation/providers/profile_providers.dart';
import 'package:bailongo/features/settings/domain/user_settings.dart';
import 'package:bailongo/features/settings/presentation/providers/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estadísticas de ejemplo: uno aprendido, dos en práctica (el de cumbia es
/// el más reciente) y el resto sin intentos.
final _stats = <String, StepStats>{
  'cucaracha': StepStats(best: 85, attempts: 5, lastAt: DateTime(2026, 10, 20)),
  'basico_adelante_atras':
      StepStats(best: 53, attempts: 7, lastAt: DateTime(2026, 10, 21)),
  'cumbia_step':
      StepStats(best: 63, attempts: 8, lastAt: DateTime(2026, 10, 25)),
};

List<Override> _overrides({Uint8List? Function(String)? thumb}) => [
      catalogProvider.overrideWith((ref) async => kRealSteps),
      currentSettingsProvider.overrideWithValue(const UserSettings()),
      userStepStatsProvider.overrideWith((ref) async => _stats),
      stepThumbnailProvider.overrideWith((ref, url) async => thumb?.call(url)),
      profileProvider.overrideWith((ref) async => const AppUser(
          uid: 'u1', email: 'ana@example.com', nombre: 'Ana Pérez')),
    ];

Future<void> _pump(WidgetTester tester, Widget page, double width,
    {double textScale = 1}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(),
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: page),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final (width, scale) in [(320.0, 1.0), (390.0, 1.0), (390.0, 1.3)]) {
    testWidgets('catálogo en pósters sin desbordes a $width px (letra $scale)',
        (tester) async {
      await _pump(tester, const CatalogPage(), width, textScale: scale);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1 de 9', findRichText: true), findsOneWidget);
      // La comprobación de izquierda/derecha vive sólo en Configuración.
      expect(find.text('Comprobar izquierda y derecha'), findsNothing);
      // Dos columnas: los dos primeros pósters comparten fila.
      final a = tester.getTopLeft(find.text('Básico (adelante y atrás)'));
      final b = tester.getTopLeft(find.text('Básico (guapeo)'));
      expect(a.dy, closeTo(b.dy, 1));
      expect(b.dx, greaterThan(a.dx));
      // Estado y mejor marca sobre el póster.
      expect(find.text('Aprendido'), findsOneWidget);
      expect(find.text('53%'), findsOneWidget);
      // Deja correr el temporizador de la vista previa (en pruebas no hay
      // reproductor de video: debe fallar en silencio).
      await tester.pump(CatalogPage.previewDelay + const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('progreso del perfil sin desbordes a $width px (letra $scale)',
        (tester) async {
      await _pump(tester, const ProfilePage(), width, textScale: scale);
      expect(tester.takeException(), isNull);
      // Sugiere el paso en práctica más reciente.
      expect(find.text('CONTINÚA PRACTICANDO'), findsOneWidget);
      expect(find.text('Mejor 63 % · 8 intentos'), findsOneWidget);
      expect(find.text('Todos los pasos'), findsOneWidget);
    });
  }
}
