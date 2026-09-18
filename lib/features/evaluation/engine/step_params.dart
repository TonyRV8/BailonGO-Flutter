import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt
/// §7-sexies). Recalibración del 2026-09-18 contra TOMAS REALES etiquetadas:
///   dart run tool/bench_real.dart --fit
///
/// Todo el motor es global (`DtwParams.defaults`) salvo los dos extremos de
/// la curva de alineación, que trabaja sobre el COSTE RELATIVO (coste /
/// coste de quedarse quieto, medido en la dispersión del propio alumno):
///
///   floor  coste ≤ floor → alineación 100.
///   max    coste ≥ max   → alineación 0.
///
/// Se eligen minimizando el error frente a las etiquetas humanas de las tomas
/// de ESE paso (ideal 100, toma regular de la profesora 70-80, alumnos 40-50,
/// Avril 67-83, bailes ajenos ≤ 16, quieto 0, más dos controles sintéticos:
/// la referencia retrasada 330 ms → ~92 y un 10 % más lenta → ~85).
///
/// Límites del ajuste, para que ningún paso quede indefendible:
///   floor 0.05-0.70   (la toma regular cuesta ~0.9: por debajo tiene que
///                      haber curva, no meseta de 100)
///   max ≤ 2.2 y max - floor ≥ 0.4 (sin acantilados)
///
/// Resultado en el banco real (100 tomas, 62 en banda, media por grupo):
///   ideal 100 · desfase 99 · lento 83 · regular 66 · Avril 53 · alumnos 46
///   · bailes ajenos 14 · quieto 0            (loss 29.4)
/// Una sola curva global para los nueve pasos daba loss 100.
///
/// Cambiar cualquier parámetro invalida la comparabilidad de las mejores
/// marcas ya guardadas en HISTORY.
const Map<String, ({double floor, double max})> _fitted = {
  'basico_adelante_atras': (floor: 0.670, max: 2.150),
  'basico_guapeo': (floor: 0.650, max: 1.890),
  'cucaracha': (floor: 0.050, max: 1.310),
  'suzy_q': (floor: 0.430, max: 1.630),
  'right_spot_turn': (floor: 0.090, max: 1.350),
  'cumbia_step': (floor: 0.670, max: 1.610),
  'cuban_break': (floor: 0.050, max: 1.230),
  'giro_punta_talon': (floor: 0.650, max: 1.050),
  'kick_flick': (floor: 0.050, max: 1.490),
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
