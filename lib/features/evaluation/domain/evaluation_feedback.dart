import '../engine/dtw_result.dart';

/// Genera el feedback cualitativo del modal de resultados (RF-10) a partir del
/// score y el componente con mayor error.
String feedbackFor(DtwResult r) {
  final worst = (r.worstComponentIndex >= 0 &&
          r.worstComponentIndex < DtwResult.componentNames.length)
      ? DtwResult.componentNames[r.worstComponentIndex]
      : null;

  if (r.score >= 85) {
    return '¡Excelente! Tu ejecución coincide muy bien con el modelo.';
  }
  if (r.score >= 60) {
    return worst == null
        ? 'Bien. Sigue puliendo los detalles.'
        : 'Bien hecho. Puedes mejorar $worst.';
  }
  if (r.score >= 40) {
    return worst == null
        ? 'Vas por buen camino, sigue practicando.'
        : 'Vas por buen camino. Enfócate en $worst.';
  }
  return worst == null
      ? 'Sigue practicando el paso con calma.'
      : 'Sigue practicando. Revisa sobre todo $worst.';
}
