import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt
/// §7-octies). Recalibración del 2026-10-05 contra el corpus ampliado, con
/// notas del revisor de 2/10 a 8/10 (antes solo había etiquetas bajas):
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
/// Se eligen minimizando el error frente a las etiquetas humanas de las tomas
/// de ESE paso, que viven en `tool/labels.json`: la referencia contra sí
/// misma 100, la toma regular de la profesora 75, cada alumno con la nota
/// que le puso el revisor (de 20 a 80), los bailes ajenos 8 y la inmovilidad
/// 0, más dos controles sintéticos (la referencia retrasada 330 ms → ~92 y
/// un 10 % más lenta → ~85).
///
/// Límites del ajuste, para que ningún paso quede indefendible:
///   floor 0.05-0.70   (la toma regular cuesta ~0.9: por debajo tiene que
///                      haber curva, no meseta de 100)
///   max ≤ 2.2 y max - floor ≥ 0.4 (sin acantilados)
///
/// Resultado en el banco real (110 tomas, 61 en banda, media por grupo):
///   ideal 100 · desfase 99 · lento 84 · regular 66 · Avril 57 · Gabo 45
///   · Abdiel 34 · bailes ajenos 15 · quieto 0
///   (pérdida 58.4; correlación de rangos con el revisor 0.95 y error medio
///   8.5 puntos sobre el total de tomas etiquetadas)
/// Una sola curva global para los nueve pasos empeora la pérdida al triple.
///
/// LÍMITE CONOCIDO, que ninguna curva arregla: sobre las 25 tomas con nota
/// directa del revisor, el costo medio de las que puntuó 6/10 o más (1.04) no
/// queda por debajo del de las que puntuó 3/10 o menos (1.03). Entre alumnos
/// reales el motor no ordena por calidad; lo que sí separa con holgura es un
/// baile ajeno (1.49), la inmovilidad (1.00) y la referencia (0.00). Ver
/// §7-octies.
///
/// Cambiar cualquier parámetro invalida la comparabilidad de las mejores
/// marcas ya guardadas en HISTORY.
const Map<String, ({double floor, double max})> _fitted = {
  'basico_adelante_atras': (floor: 0.650, max: 2.190),
  'basico_guapeo': (floor: 0.690, max: 1.810),
  'cucaracha': (floor: 0.090, max: 1.290),
  'suzy_q': (floor: 0.090, max: 2.010),
  'right_spot_turn': (floor: 0.470, max: 1.150),
  'cumbia_step': (floor: 0.690, max: 1.770),
  'cuban_break': (floor: 0.050, max: 1.090),
  'giro_punta_talon': (floor: 0.630, max: 1.050),
  'kick_flick': (floor: 0.050, max: 1.850),
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
