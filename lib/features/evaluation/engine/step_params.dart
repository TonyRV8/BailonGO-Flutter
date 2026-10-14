import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt
/// §7-decies). Calibración final del 2026-10-13 sobre 72 grabaciones de cinco
/// personas, con notas del revisor de 1/10 a 8.5/10:
///   python tool/build_labels.py
///   dart run tool/bench_real.dart --wsweep
///
/// Todo el motor es global (`DtwParams.defaults`) salvo los dos extremos de
/// la curva de alineación, que trabaja sobre el COSTE RELATIVO (coste /
/// coste de quedarse quieto, medido en la dispersión del propio alumno):
///
///   floor  coste ≤ floor → alineación 100.
///   max    coste ≥ max   → alineación 0.
///
/// Se eligen minimizando el error frente a las notas humanas de las tomas de
/// ESE paso, que viven en `tool/labels.json`: la referencia contra sí misma
/// 100, la toma regular de la profesora 75, cada alumno con su nota (de 10 a
/// 85), los bailes ajenos 8 y la inmovilidad 0. Las tomas de Avril llevan
/// medio punto de cortesía sobre la nota del revisor, decisión declarada que
/// recoge que son el techo del corpus al no haber material de 9 o 10. El banco añade tres controles
/// sintéticos por paso: la referencia retrasada 330 ms → ~92, un 10 % más
/// lenta → ~85 y dos variantes con el temblor y la amplitud de una captura
/// real → 95.
///
/// Ese último control es el que mantiene alcanzable el sobresaliente. Sin él
/// el ajuste no tiene ninguna toma que le diga dónde empieza el 90 %, porque
/// la referencia contra sí misma da 100 con cualquier umbral y la mejor
/// ejecución humana del corpus está calificada con 8/10.
///
/// Límites del ajuste, para que ningún paso quede indefendible:
///   floor 0.05-1.00   por encima de 1.0 aprobaría un baile ajeno al paso,
///                     cuyo costo arranca en 1.07
///   max ≤ 2.2 y max - floor ≥ 0.4 (sin acantilados)
///
/// Resultado en el banco (154 casos, 81 en banda, media por grupo):
///   referencia 100 · captura real de ella 98 · retrasada 99 · 10 % más
///   lenta 83 · toma regular 71 (58-78, ninguna por encima de su banda)
///   · Avril 60 (máximo 81) · Toto 61 · Gabo 57 · Abdiel 42 · bailes ajenos 17
///   · inmovilidad 0
///   (correlación de rangos con el revisor 0.92 sobre todas las tomas
///   calificadas y 0.31 sobre las 51 con nota individual, frente a 0.05 dos
///   vueltas atrás)
/// Una sola curva global para los nueve pasos empeora la pérdida al triple.
///
/// La toma imperfecta de la profesora pesa 6 en el ajuste, el triple que una
/// toma de alumno. Es la única que calificó la propia experta y marca dónde
/// está el 75 %; con peso 2 el ajuste la sacrificaba para perseguir notas de
/// alumno que quedaban fuera de alcance igualmente, y llegó a darle 90 al
/// Right Spot Turn imperfecto subiendo su umbral a 0.89. Corregido, ninguna
/// pasa de 78.
///
/// LÍMITE CONOCIDO: el motor mide el parecido con UNA grabación concreta de
/// la profesora, no si el paso está bien hecho. Una ejecución que el revisor
/// puntúa 8.5 cuesta 1.01 de media, frente a 1.00 de quedarse quieto y 1.07
/// del baile ajeno más parecido, así que premiarla más haría aprobar a una
/// coreografía que no corresponde al paso.
///
/// Se descartó por medición que esto venga de la complexión del alumno o de
/// la altura de la cámara: deformar la referencia (piernas un 25 % más largas
/// o más cortas, cámara bastante más alta) y evaluarla contra sí misma sigue
/// dando 94-100, porque el comparador mide cada característica en unidades de
/// la dispersión del propio usuario y un factor de escala se cancela. La
/// sonda está en `tool/probe_body.dart`.
///
/// Lo que sí separa con holgura: la referencia (0.00), una captura real de
/// ella misma (0.22), la inmovilidad (1.00) y un baile ajeno (1.46). Romper
/// el techo pide varias referencias por paso, para pasar de "¿te pareces a
/// esta toma?" a "¿está tu ejecución dentro de lo que cuenta como este
/// paso?". Ver §7-decies.
///
/// Cambiar cualquier parámetro invalida la comparabilidad de las mejores
/// marcas ya guardadas en HISTORY.
const Map<String, ({double floor, double max})> _fitted = {
  'basico_adelante_atras': (floor: 0.910, max: 2.190),
  'basico_guapeo': (floor: 0.850, max: 1.850),
  'cucaracha': (floor: 0.370, max: 1.310),
  'suzy_q': (floor: 0.070, max: 2.170),
  'right_spot_turn': (floor: 0.050, max: 1.550),
  'cumbia_step': (floor: 0.810, max: 1.790),
  'cuban_break': (floor: 0.070, max: 1.490),
  'giro_punta_talon': (floor: 0.290, max: 1.810),
  'kick_flick': (floor: 0.070, max: 1.710),
};

/// Parámetros del paso indicado; los defaults globales si no está calibrado
/// (p.ej. los pasos de prueba temporales).
DtwParams paramsFor(String pasoId) {
  final f = _fitted[pasoId];
  if (f == null) return DtwParams.defaults;
  return DtwParams.defaults.copyWith(alignNoiseFloor: f.floor, alignMax: f.max);
}

/// Ids con calibración propia. Útil para avisos en herramientas dev.
Iterable<String> get calibratedStepIds => _fitted.keys;
