import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bailongo/features/catalog/data/catalog_seed.dart';
import 'package:bailongo/features/viewer3d/domain/step_animations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nombres de las animaciones guardadas en el chunk JSON del GLB.
Set<String> _glbAnimations(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(utf8.decode(bytes.sublist(0, 4)), 'glTF');
  final jsonLength = data.getUint32(12, Endian.little);
  final gltf = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  return {
    for (final a in gltf['animations'] as List) (a as Map)['name'] as String,
  };
}

void main() {
  test('el GLB contiene exactamente las 9 animaciones mapeadas', () {
    expect(
        _glbAnimations(StepAnimations.modelAsset), StepAnimations.all.toSet());
  });

  test('cada paso WSF del catálogo tiene su animación', () {
    const expected = {
      'basico_adelante_atras': 'basico_3d',
      'basico_guapeo': 'guapeo_3d',
      'cucaracha': 'cucaracha_3d',
      'suzy_q': 'suzyq_3d',
      'right_spot_turn': 'vuelta_3d',
      'cumbia_step': 'cumbia_3d',
      'cuban_break': 'cuban_3d',
      'giro_punta_talon': 'toeheel_3d',
      'kick_flick': 'kickflick_3d',
    };
    for (final step in kCatalogSeed) {
      expect(StepAnimations.forStep(step.id), expected[step.id],
          reason: step.id);
      // El nombre visible resuelve igual que el id.
      expect(StepAnimations.forStep(step.nombre), expected[step.id],
          reason: step.nombre);
    }
  });

  test('alias y texto libre', () {
    expect(StepAnimations.forStep('basico'), 'basico_3d');
    expect(StepAnimations.forStep('right spot turn'), 'vuelta_3d');
    expect(StepAnimations.forStep('Right Spot Turn'), 'vuelta_3d');
    expect(StepAnimations.forStep('Básico (guapeo)'), 'guapeo_3d');
    expect(StepAnimations.forStep('Suzy Q'), 'suzyq_3d');
    expect(StepAnimations.forStep('toe heel'), 'toeheel_3d');
    expect(StepAnimations.forStep('kickflick_3d'), 'kickflick_3d');
    expect(StepAnimations.forStep('paso_prueba'), isNull);
    expect(StepAnimations.forStep(''), isNull);
  });
}
