import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt
/// §7-undecies). Calibración final del 2026-10-21 sobre 81 grabaciones de
/// seis personas, con notas del revisor de 1/10 a 10/10:
///   python tool/extract_revisados.py tool/landmarks_revisados.json
///   python tool/build_labels.py
///   dart run tool/bench_real.dart --fit
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
/// El ancla del extremo alto ya no es sintética: `Profa_<Paso>_calif10` son
/// los nueve pasos repetidos por la profesora y calificados 10 por ella misma
/// (objetivo 100, peso 8, una por carpeta de paso). Hasta esta vuelta
/// el ajuste no tenía ninguna toma humana que le dijera dónde empieza el
/// sobresaliente, porque la referencia contra sí misma da 100 con cualquier
/// umbral y la mejor ejecución de alumno está en 8.5/10.
///
/// Lo que esas nueve tomas miden, y es el dato más revelador de la
/// calibración: la MISMA profesora repitiendo el MISMO paso cuesta 0.66 de
/// media (0.43-0.92), cuando quedarse quieto cuesta 1.00. Dos ejecuciones
/// correctas del mismo paso están casi tan lejos entre sí como una ejecución
/// correcta de una mala. Por eso los umbrales de esta vuelta son más altos:
/// no es indulgencia, es que antes estaban puestos por debajo de la variación
/// normal entre dos pasadas buenas.
///
/// Límites del ajuste, para que ningún paso quede indefendible:
///   floor 0.05-1.00   por encima de 1.0 aprobaría un baile ajeno al paso,
///                     cuyo costo arranca en 1.07
///   max ≤ 2.2 y max - floor ≥ 0.4 (sin acantilados)
///
/// ESCALA +10 (2026-10-21, segunda pasada): todas las etiquetas de alumno
/// suben 10 puntos (`ALUMNO_BONO` en build_labels.py). Probando la app, las
/// notas salían más duras que el juicio de quien baila: un Right Spot Turn
/// decente marcaba 13 de alineación. Es un ajuste DECLARADO de la escala, no
/// una nota nueva del revisor, y mueve el listón sin tocar los algoritmos.
/// Cuesta orden: el acuerdo de rangos entre alumnos baja de 0.34 a 0.29,
/// porque comprimir la escala hacia arriba junta tomas que antes separaba.
///
/// Resultado en el banco (163 casos con nota, 76 en banda, media por grupo):
///   referencia 100 · captura real de ella 100 · retrasada 99 · tomas de 10
///   de la profesora 90 (81-96) · 10 % más lenta 93 · toma regular 78
///   (62-85) · Avril 69 (máximo 87) · Gabo 67 · Toto 64 · Abdiel 49
///   · Primo 44 · bailes ajenos 21 (máximo 42) · inmovilidad 0
///   (correlación de rangos con el revisor 0.85 sobre todas las tomas
///   calificadas, 0.29 sobre las 51 de alumno con nota individual y 0.55
///   sobre las 60 que incluyen las nueve tomas de 10)
/// Una sola curva global para los nueve pasos empeora la pérdida al triple.
///
/// El otro cambio de esta vuelta está en `DtwParams`: `rhythmMaxLag` 12 → 18
/// (±0.6 s). Ir medio tiempo descolocado en un momento suelto no es bailar
/// fuera de compás, y con ±0.4 s las tomas de 10 perdían tramos enteros. Es
/// el único aflojado que BAJA la pérdida (97.3 → 88.3 antes de reajustar
/// umbrales) en vez de subirla.
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
/// Se midió la salida evidente —usar las tomas de 10 como SEGUNDA referencia
/// y quedarse con el costo mínimo contra las dos (`tool/probe_multiref.dart`)—
/// y no sirve: las tomas de alumno bajan 0.06-0.08 de costo y los bailes
/// ajenos bajan 0.07, o sea lo mismo. Dos referencias aflojan el listón para
/// todos en vez de separar mejor. Haría falta otra representación, no más
/// referencias de la misma clase.
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
  'basico_guapeo': (floor: 0.850, max: 1.810),
  'cucaracha': (floor: 0.490, max: 1.310),
  'suzy_q': (floor: 0.270, max: 1.990),
  'right_spot_turn': (floor: 0.690, max: 1.610),
  'cumbia_step': (floor: 0.810, max: 1.810),
  'cuban_break': (floor: 0.470, max: 1.330),
  'giro_punta_talon': (floor: 0.670, max: 1.690),
  'kick_flick': (floor: 0.530, max: 1.390),
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
