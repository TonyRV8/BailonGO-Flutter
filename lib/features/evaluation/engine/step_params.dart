import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt
/// §7-quinquies). Recalibración del 2026-09-17 tras pruebas en vivo en las que
/// guapeo, suzy q y right spot turn daban alineación 0 bailando bien:
///   dart run tool/bench.dart tool/landmarks.json --fit
///
/// Todo el motor es global (`DtwParams.defaults`) salvo los dos extremos de
/// la curva de alineación, que trabaja sobre el COSTE RELATIVO (coste /
/// coste de quedarse quieto):
///
///   max    la toma de 5/10 de la profesora (limpia y en vivo) da ~50 %.
///   floor  el menor suelo con el que un ALUMNO que baila bien —con su propio
///          braceo, amplitud y fraseo, en cámara real— llega a ~85 %. Si no
///          llega sin subir la toma de 5, el que más se acerca.
///
/// Límites: floor 0.1-0.7, max 0.9-2.2, max - floor ≥ 0.25, y quedarse quieto
/// desde la mitad del intento ≤ ~55 %.
///
/// Resultado en el banco (objetivo entre paréntesis):
///   alumno bien 80-86 (85), salvo right_spot_turn 65 · toma de 5: 49-55 (50)
///   profesora en cámara real 94-100 · quieto 0-1 (0) · quieto desde la mitad
///   17-57 (30) · otro paso 9-44
///
/// Cambiar cualquier parámetro invalida la comparabilidad de las mejores
/// marcas ya guardadas en HISTORY.
const Map<String, ({double floor, double max})> _fitted = {
  'basico_adelante_atras': (floor: 0.700, max: 1.139),
  'basico_guapeo': (floor: 0.600, max: 0.942),
  'cucaracha': (floor: 0.300, max: 1.057),
  'suzy_q': (floor: 0.450, max: 1.059),
  'right_spot_turn': (floor: 0.500, max: 0.900),
  'cumbia_step': (floor: 0.350, max: 0.900),
  'cuban_break': (floor: 0.500, max: 0.902),
  'giro_punta_talon': (floor: 0.600, max: 0.900),
  'kick_flick': (floor: 0.200, max: 1.200),
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
