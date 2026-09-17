/// Lleva los fotogramas capturados en vivo a la misma rejilla temporal que la
/// referencia (un vector cada 33 ms).
///
/// Por qué hace falta: la referencia se muestrea exactamente cada 33 ms, pero
/// en vivo el detector no siempre llega a 30 fps (la app descarta la imagen si
/// la anterior sigue en proceso) y además pierde fotogramas sin pose. Sin
/// remuestrear, un teléfono lento entrega 1 fotograma por cada 2 de la
/// referencia y el DTW lo interpreta como que el alumno baila al doble de
/// velocidad: el ritmo se hunde aunque el baile esté perfecto.
class FrameResampler {
  FrameResampler._();

  /// Separación de la rejilla de la referencia.
  static const int stepMs = 33;

  /// Un hueco mayor que esto no se interpola: se CONGELA la última pose. Si el
  /// alumno sale de cuadro no debe inventarse un movimiento suave que no hizo.
  static const int maxInterpolateGapMs = 400;

  /// [frames] y [timesMs] van en paralelo y en orden creciente de tiempo
  /// (ms desde el inicio de la captura). Devuelve `durationMs / stepMs`
  /// vectores. Antes del primer fotograma se repite el primero.
  static List<List<double>> toGrid(
    List<List<double>> frames,
    List<int> timesMs, {
    required int durationMs,
  }) {
    assert(frames.length == timesMs.length);
    if (frames.isEmpty) return const [];
    final count = (durationMs / stepMs).round();
    final out = <List<double>>[];
    var j = 0;
    for (var k = 0; k < count; k++) {
      final t = k * stepMs;
      while (j + 1 < timesMs.length && timesMs[j + 1] <= t) {
        j++;
      }
      if (t <= timesMs[0]) {
        out.add(frames[0]);
        continue;
      }
      if (j + 1 >= timesMs.length) {
        out.add(frames[j]);
        continue;
      }
      final t0 = timesMs[j], t1 = timesMs[j + 1];
      if (t1 - t0 > maxInterpolateGapMs || t1 == t0) {
        out.add(frames[j]);
        continue;
      }
      final a = frames[j], b = frames[j + 1];
      final u = (t - t0) / (t1 - t0);
      out.add(List<double>.generate(a.length, (c) => a[c] + (b[c] - a[c]) * u,
          growable: false));
    }
    return out;
  }
}
