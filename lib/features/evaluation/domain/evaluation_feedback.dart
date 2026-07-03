import '../engine/dtw_result.dart';

/// Feedback de un tiempo del paso (inicio/medio/final): scores del segmento
/// más consejos accionables (RF-10, desglose por tiempo).
class SegmentFeedback {
  const SegmentFeedback({
    required this.label,
    required this.alignmentScore,
    required this.rhythmScore,
    required this.score,
    required this.tips,
  });

  final String label;
  final int alignmentScore;
  final int rhythmScore;

  /// Precisión del segmento (RNF-06 por tiempo).
  final int score;

  /// Consejos concretos ("levanta más el pie…", "ve más lento…"). Vacío si el
  /// segmento salió bien.
  final List<String> tips;
}

/// Feedback completo de un intento: resumen global + desglose por tiempo.
class EvaluationFeedback {
  const EvaluationFeedback({required this.overall, required this.segments});

  final String overall;
  final List<SegmentFeedback> segments;
}

const List<String> _segmentLabels = ['Inicio', 'Medio', 'Final'];

/// Umbral de alineación por segmento debajo del cual se dan consejos.
const int _adviseAlignBelow = 85;

/// Magnitud señada mínima (diff normalizada por rango) para dar dirección.
const double _signedThreshold = 0.02;

/// Desviación de tempo señada mínima para aconsejar más lento / más rápido.
const double _tempoThreshold = 0.05;

/// Ritmo por segmento debajo del cual se aconseja constancia (sin dirección).
const int _adviseRhythmBelow = 70;

/// Máximo de consejos de alineación por segmento.
const int _maxAlignTips = 2;

/// Construye el feedback cualitativo desglosado en los 3 tiempos del paso.
EvaluationFeedback buildFeedback(DtwResult r) {
  final segments = List<SegmentFeedback>.generate(3, (s) {
    final tips = <String>[];

    // Consejos de alineación: peores componentes del segmento con dirección.
    if (s < r.segmentAlignment.length &&
        r.segmentAlignment[s] < _adviseAlignBelow &&
        s < r.segmentComponentErrors.length) {
      final errors = r.segmentComponentErrors[s];
      final signed =
          s < r.segmentSignedErrors.length ? r.segmentSignedErrors[s] : const <double>[];
      final order = List<int>.generate(errors.length, (i) => i)
        ..sort((a, b) => errors[b].compareTo(errors[a]));
      for (final idx in order.take(_maxAlignTips)) {
        if (errors[idx] <= 0) break;
        final sd = idx < signed.length ? signed[idx] : 0.0;
        tips.add(_alignmentTip(idx, sd));
      }
    }

    // Consejo de ritmo: dirección del tempo (adelantado/atrasado).
    if (s < r.segmentTempo.length) {
      final tempo = r.segmentTempo[s];
      if (tempo > _tempoThreshold) {
        tips.add('Vas adelantado: ve un poco más lento.');
      } else if (tempo < -_tempoThreshold) {
        tips.add('Vas atrasado: ve un poco más rápido.');
      } else if (s < r.segmentRhythm.length &&
          r.segmentRhythm[s] < _adviseRhythmBelow) {
        tips.add('Mantén un ritmo más constante.');
      }
    }

    return SegmentFeedback(
      label: _segmentLabels[s],
      alignmentScore: s < r.segmentAlignment.length ? r.segmentAlignment[s] : 0,
      rhythmScore: s < r.segmentRhythm.length ? r.segmentRhythm[s] : 0,
      score: s < r.segmentScore.length ? r.segmentScore[s] : 0,
      tips: tips,
    );
  });

  return EvaluationFeedback(overall: _overallFor(r), segments: segments);
}

String _overallFor(DtwResult r) {
  if (r.score >= 85) {
    return '¡Excelente! Tu ejecución coincide muy bien con el modelo.';
  }
  if (r.score >= 60) return 'Bien hecho. Revisa los consejos de cada tiempo.';
  if (r.score >= 40) {
    return 'Vas por buen camino. Trabaja los tiempos marcados abajo.';
  }
  return 'Sigue practicando con calma, tiempo por tiempo.';
}

/// Consejo direccional para el componente [idx] según la diferencia señada
/// media (usuario − referencia, normalizada). Convención de coordenadas de
/// imagen sin espejo: X crece a la derecha de la imagen (= lado izquierdo de
/// la persona), Y crece hacia abajo.
String _alignmentTip(int idx, double signed) {
  final pos = signed > _signedThreshold;
  final neg = signed < -_signedThreshold;
  if (!pos && !neg) {
    // Error alto pero oscilante (sin dirección estable): consejo neutro.
    final name = idx < DtwResult.componentNames.length
        ? DtwResult.componentNames[idx]
        : 'ese movimiento';
    return 'Revisa $name.';
  }
  switch (idx) {
    // Ángulo de rodilla (180° = estirada): mayor que el modelo = muy estirada.
    case 0:
      return pos
          ? 'Flexiona un poco más la rodilla izquierda.'
          : 'Estira un poco más la rodilla izquierda.';
    case 1:
      return pos
          ? 'Flexiona un poco más la rodilla derecha.'
          : 'Estira un poco más la rodilla derecha.';
    // Inclinación de pierna (1 = vertical).
    case 2:
      return pos
          ? 'Inclina un poco más la pierna izquierda.'
          : 'Mantén la pierna izquierda más vertical.';
    case 3:
      return pos
          ? 'Inclina un poco más la pierna derecha.'
          : 'Mantén la pierna derecha más vertical.';
    case 4:
      return pos
          ? 'Junta un poco más los pies.'
          : 'Separa un poco más los pies.';
    // Altura de tobillo (Y hacia abajo: mayor = pie más abajo).
    case 5:
      return pos
          ? 'Levanta más el pie izquierdo.'
          : 'No levantes tanto el pie izquierdo.';
    case 6:
      return pos
          ? 'Levanta más el pie derecho.'
          : 'No levantes tanto el pie derecho.';
    // Posición lateral (lado izquierdo de la persona = X positiva).
    case 7:
      return pos
          ? 'Abre un poco menos el pie izquierdo, acércalo al centro.'
          : 'Abre un poco más el pie izquierdo hacia afuera.';
    case 8:
      return pos
          ? 'Abre un poco más el pie derecho hacia afuera.'
          : 'Abre un poco menos el pie derecho, acércalo al centro.';
    case 9:
      return pos
          ? 'Lleva la rodilla izquierda más hacia el centro.'
          : 'Abre un poco más la rodilla izquierda.';
    case 10:
      return pos
          ? 'Abre un poco más la rodilla derecha.'
          : 'Lleva la rodilla derecha más hacia el centro.';
    // Orientación del pie (punta − talón en X).
    case 11:
      return pos
          ? 'Gira la punta del pie izquierdo hacia adentro.'
          : 'Gira la punta del pie izquierdo hacia afuera.';
    case 12:
      return pos
          ? 'Gira la punta del pie derecho hacia afuera.'
          : 'Gira la punta del pie derecho hacia adentro.';
    // Pitch del pie (positivo = punta arriba).
    case 13:
      return pos
          ? 'Baja la punta del pie izquierdo.'
          : 'Levanta más la punta del pie izquierdo.';
    case 14:
      return pos
          ? 'Baja la punta del pie derecho.'
          : 'Levanta más la punta del pie derecho.';
    // Ángulo de brazo (180° = estirado).
    case 15:
      return pos
          ? 'Flexiona un poco más el brazo izquierdo.'
          : 'Estira un poco más el brazo izquierdo.';
    case 16:
      return pos
          ? 'Flexiona un poco más el brazo derecho.'
          : 'Estira un poco más el brazo derecho.';
    // Tilt de hombros (positivo = hombro izquierdo más abajo).
    case 17:
      return pos
          ? 'Sube el hombro izquierdo para nivelar los hombros.'
          : 'Sube el hombro derecho para nivelar los hombros.';
    // Posición lateral de manos.
    case 18:
      return pos
          ? 'Lleva la mano izquierda más hacia el centro.'
          : 'Lleva la mano izquierda más hacia afuera.';
    case 19:
      return pos
          ? 'Lleva la mano derecha más hacia afuera.'
          : 'Lleva la mano derecha más hacia el centro.';
    // Altura de manos (Y hacia abajo: mayor = mano más abajo).
    case 20:
      return pos
          ? 'Sube más la mano izquierda.'
          : 'Baja un poco la mano izquierda.';
    case 21:
      return pos ? 'Sube más la mano derecha.' : 'Baja un poco la mano derecha.';
    default:
      return 'Revisa ese movimiento con el video modelo.';
  }
}
