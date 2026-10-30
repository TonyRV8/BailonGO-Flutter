/// Curva de presentación de la nota (implementar_pasos.txt §7-duodecies).
///
/// QUÉ ES: un remapeo monótono de 0-100 a 0-100 que se aplica a la nota de
/// alineación y a la de ritmo DESPUÉS de medirlas. No toca la medición: ni la
/// distancia euclidiana ponderada, ni el DTW con banda de Sakoe-Chiba, ni los
/// umbrales por paso. Solo cambia cómo se presenta lo medido.
///
/// POR QUÉ: probando la app, la escala no se sentía repartida como la
/// percibe quien baila. Dos quejas concretas y opuestas entre sí:
///   * en la zona media (50-75) las notas salían 5-10 puntos altas: un 75 se
///     sentía un 65;
///   * de 80 para arriba costaba demasiado subir, así que el 90-100 quedaba
///     casi fuera de alcance.
/// Ningún parámetro del motor hace las dos cosas a la vez: subir la exigencia
/// en el centro (con la potencia de la curva de alineación o con el umbral de
/// correlación del ritmo) baja también el extremo alto, que es lo que NO se
/// quería tocar. Se midió, y por eso existe este remapeo aparte.
///
/// PROPIEDADES, que son las que lo hacen defendible:
///   * es estrictamente creciente, así que NO cambia el orden de ningún par
///     de intentos: la correlación de rangos con el revisor es exactamente la
///     misma antes y después;
///   * deja fijos los extremos (0 → 0, 100 → 100), que es donde la escala ya
///     se comportaba bien;
///   * el punto neutro está en 84: por debajo baja la nota, por encima la
///     sube.
///
/// Es una decisión de producto DECLARADA, igual que el +10 de las etiquetas
/// de alumno, no una mejora de medición.
///
/// DÓNDE SE APLICA: a la nota de alineación y a la de ritmo, ya con sus
/// factores de cobertura y espejo, justo antes de combinarlas. Así el total
/// sigue siendo exactamente 60 % de la primera más 40 % de la segunda
/// (RNF-06) y los números que ve el usuario cuadran entre sí, tanto el global
/// como el desglose por tramo.
///
/// Por eso la tabla de abajo es MÁS pronunciada que el efecto final: como el
/// total es una media ponderada de dos componentes que casi nunca coinciden,
/// una bajada de 13 puntos en cada componente se traduce en unos 6-7 en el
/// total. Los puntos se ajustaron midiendo sobre las 163 tomas del banco
/// hasta que el efecto NETO fue el pedido:
///
///   nota medida   40-49  50-59  60-69  70-79  80-89  90-99
///   cambio medio   -7.7   -7.4   -6.4   -4.9   -1.6   +0.1
class ScoreCurve {
  ScoreCurve._();

  /// Puntos de la curva: nota medida → nota mostrada. Entre dos puntos se
  /// interpola en línea recta. Para cambiar el reparto de la escala se tocan
  /// estos pares y nada más.
  static const List<(double, double)> anchors = [
    (0, 0),
    (20, 18),
    (30, 23),
    (40, 31),
    (50, 38),
    (60, 47),
    (70, 57),
    (76, 67),
    (80, 77), // el cruce con la identidad cae aquí al lado, ~81
    (84, 86),
    (88, 93),
    (92, 97),
    (96, 99),
    (100, 100),
  ];






  /// Interruptor para medir A/B desde el banco (`--sincurva`). En la app
  /// siempre está activa; existe para poder imprimir la tabla con y sin curva
  /// sin recompilar.
  static bool enabled = true;

  /// Nota mostrada para una nota medida [score] (0-100).
  static double apply(double score) {
    if (!enabled) return score;
    if (score <= 0) return 0;
    if (score >= 100) return 100;
    for (var i = 1; i < anchors.length; i++) {
      final (x1, y1) = anchors[i];
      if (score <= x1) {
        final (x0, y0) = anchors[i - 1];
        final t = (score - x0) / (x1 - x0);
        return y0 + (y1 - y0) * t;
      }
    }
    return score;
  }

  /// Igual que [apply] pero devolviendo entero, que es como viajan las notas
  /// por el resto del motor.
  static int applyInt(int score) => apply(score.toDouble()).round();
}
