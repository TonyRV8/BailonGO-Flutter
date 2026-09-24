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

    test('una marca de tiempo del intento anterior no aplana la captura', () {
      // Bug de reintento: la imagen que empezó a procesarse antes del ¡YA!
      // entraba con el tiempo del reloj parado (la duración del intento
      // anterior). Como quedaba la primera de la lista y superaba toda la
      // ventana, la rejilla salía constante y el intento puntuaba 0 %.
      final frames = <List<double>>[
        [999.0], // llegó fuera de orden, con el tiempo del intento anterior
        for (var t = 0; t < 1000; t += 33) [t.toDouble()],
      ];
      final times = <int>[
        1000,
        for (var t = 0; t < 1000; t += 33) t,
      ];
      final grid = FrameResampler.toGrid(frames, times, durationMs: 1000);
      expect(grid.length, 30);
      // La captura conserva su movimiento: no es una pose repetida.
      expect(grid.map((f) => f[0]).toSet().length, greaterThan(20));
      expect(grid.first[0], closeTo(0, 1));
    });
  });
}
