/// Métricas acumuladas del usuario en un paso: mejor precisión histórica
/// (RF-06 / RN-04) y número de intentos realizados.
///
/// Ambas se derivan de la colección HISTORY, donde cada intento evaluado deja
/// un documento. No hay contador aparte: así el número de intentos no puede
/// desincronizarse de los intentos guardados, y los botones de "reiniciar
/// progreso" (dev) lo dejan en 0 sin tocar nada más.
class StepStats {
  const StepStats({this.best, this.attempts = 0});

  /// Mejor `scores.total` del paso, `null` si aún no hay intentos.
  final double? best;

  /// Cuántos intentos evaluados hay guardados de este paso.
  final int attempts;

  static const StepStats empty = StepStats();
}
