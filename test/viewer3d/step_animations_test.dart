import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bailongo/features/catalog/data/catalog_seed.dart';
import 'package:bailongo/features/viewer3d/domain/step_animations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chunk JSON de un GLB.
Map<String, dynamic> _gltf(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(utf8.decode(bytes.sublist(0, 4)), 'glTF');
  final jsonLength = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
}

void main() {
  test('el maniquí está entre los personajes', () {
    expect(StepAnimations.characters.map((c) => c.asset),
        contains(StepAnimations.modelAsset));
  });

  // Cada personaje es un GLB con las mismas animaciones, pista y cuadros.
  for (final character in StepAnimations.characters) {
    group(character.label, () {
      test('contiene exactamente las 9 animaciones mapeadas', () {
        final gltf = _gltf(character.asset);
        expect({
          for (final a in gltf['animations'] as List)
            (a as Map)['name'] as String,
        }, StepAnimations.all.toSet());
      });

      test('incluye el dance grid en la escena', () {
        final gltf = _gltf(character.asset);
        final nodes = gltf['nodes'] as List;
        final scene = (gltf['scenes'] as List).first as Map;
        final roots = [
          for (final i in scene['nodes'] as List) nodes[i]['name'],
        ];
        expect(roots, contains(StepAnimations.danceGridNode));
      });

      test(
          'los cuadros del piso empiezan apagados y cada paso los anima '
          'todos', () {
        // Un relleno con escala 1 por defecto y sin canal en algún paso se
        // veía "siempre prendido" en ese paso.
        final gltf = _gltf(character.asset);
        final nodes = gltf['nodes'] as List;
        final pads = <int>{
          for (var i = 0; i < nodes.length; i++)
            if ((nodes[i]['name'] as String).startsWith('pisada_')) i,
        };
        expect(pads, hasLength(8));
        for (final i in pads) {
          final scale = (nodes[i]['scale'] as List?)?.cast<num>();
          expect(scale, isNotNull, reason: nodes[i]['name'] as String);
          expect(scale!.every((s) => s < 0.01), isTrue,
              reason: nodes[i]['name'] as String);
        }
        for (final a in gltf['animations'] as List) {
          final animated = {
            for (final c in a['channels'] as List)
              if (c['target']['path'] == 'scale') c['target']['node'] as int,
          };
          expect(animated.containsAll(pads), isTrue,
              reason: a['name'] as String);
        }
      });
    });
  }

  test('cada animación tiene un conteo de tiempos válido', () {
    for (final a in StepAnimations.all) {
      expect(StepAnimations.beatsFor(a), greaterThan(0), reason: a);
    }
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
