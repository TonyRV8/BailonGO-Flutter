import 'dart:io';

import 'package:bailongo/features/catalog/domain/step_weights.dart';
import 'package:bailongo/features/evaluation/domain/voice_guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada paso real tiene voz guía', () {
    expect(kVoiceGuides.keys.toSet(), kRealStepIds.toSet());
  });

  test('cada voz guía existe y está declarada en pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final path in kVoiceGuides.values) {
      expect(File('assets/$path').existsSync(), isTrue, reason: path);
      expect(pubspec, contains('- assets/$path'), reason: path);
    }
  });
}
