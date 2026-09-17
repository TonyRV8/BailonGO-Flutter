import 'package:bailongo/features/evaluation/engine/frame_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameResampler.toGrid', () {
    test('devuelve un vector por cada 33 ms de la duración', () {
      final grid = FrameResampler.toGrid(
        [
          [0.0],
          [1.0],
        ],
        [0, 1000],
        durationMs: 990,
      );
      expect(grid.length, 30);
    });

    test('interpola linealmente entre fotogramas cercanos', () {
      final grid = FrameResampler.toGrid(
        [
          [0.0],
          [66.0],
        ],
        [0, 66],
        durationMs: 99,
      );
      expect(grid[0][0], closeTo(0, 1e-9));
      expect(grid[1][0], closeTo(33, 1e-9));
      expect(grid[2][0], closeTo(66, 1e-9));
    });

    test('antes del primer fotograma repite el primero', () {
      final grid = FrameResampler.toGrid(
        [
          [5.0],
          [6.0],
        ],
        [120, 150],
        durationMs: 198,
      );
      expect(grid[0][0], 5.0);
      expect(grid[3][0], 5.0);
    });

    test('un hueco largo congela la última pose en vez de inventar movimiento',
        () {
      final grid = FrameResampler.toGrid(
        [
          [0.0],
          [100.0],
        ],
        [0, 2000],
        durationMs: 2000,
      );
      expect(grid[30][0], 0.0);
    });

    test('sin fotogramas -> vacío', () {
      expect(FrameResampler.toGrid([], [], durationMs: 1000), isEmpty);
    });
  });
}
