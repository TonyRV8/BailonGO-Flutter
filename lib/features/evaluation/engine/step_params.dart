import 'dtw_params.dart';

/// Parámetros de evaluación AJUSTADOS POR PASO (implementar_pasos.txt §7-ter).
///
/// Calibración del 2026-09-13 con el banco de PC:
///   `dart run tool/calibrate.dart tool/landmarks.json --fit`
///
/// Cada paso tiene su propio (alignNoiseFloor, alignMax) obtenido por bisección
/// para que su toma "regular" —la que la experta puntúa 5/10— dé exactamente
/// 50 %. El control ideal-vs-ideal da 100 % en los nueve.
///
/// POR QUÉ POR PASO Y NO GLOBAL: el coste normalizado de la toma regular varía
/// 25x entre pasos (0.023 en el básico a 0.576 en kick_flick). Ninguna curva
/// global puede mapear ese rango a una banda común: el mejor juego global
/// encontrado dejaba 4 de 9 pasos fuera, con dos clavados en 40 por saturación.
///
/// LIMITACIÓN QUE HAY QUE DECLARAR EN LA MEMORIA: se ajustan 2 parámetros por
/// paso contra 1 sola muestra etiquetada por paso. Eso fija la escala en dos
/// puntos (0 % de error → 100 %, la toma regular → 50 %) pero NO valida la
/// forma de la curva entre medias. Para eso harían falta más tomas por paso
/// con notas distintas (p.ej. una de 7-8/10 y una de 2-3/10).
///
/// `alignCurvePower` se deja en el valor por defecto (2.0) a propósito: con una
/// sola muestra por paso no hay información para ajustar también la curvatura.
const Map<String, DtwParams> _fitted = {
  'basico_adelante_atras': DtwParams(
    alignNoiseFloor: 0.0149,
    alignMax: 0.1991,
  ),
  'basico_guapeo': DtwParams(
    alignNoiseFloor: 0.0131,
    alignMax: 0.0909,
  ),
  'cucaracha': DtwParams(
    alignNoiseFloor: 0.1067,
    alignMax: 0.6500,
  ),
  'suzy_q': DtwParams(
    alignNoiseFloor: 0.0177,
    alignMax: 0.1026,
  ),
  'right_spot_turn': DtwParams(
    alignNoiseFloor: 0.0296,
    alignMax: 0.1695,
  ),
  'cumbia_step': DtwParams(
    alignNoiseFloor: 0.0672,
    alignMax: 0.3545,
  ),
  'cuban_break': DtwParams(
    alignNoiseFloor: 0.0217,
    alignMax: 0.1256,
  ),
  'giro_punta_talon': DtwParams(
    alignNoiseFloor: 0.0322,
    alignMax: 0.2346,
  ),
  'kick_flick': DtwParams(
    alignNoiseFloor: 0.1630,
    alignMax: 0.8602,
  ),
};

/// Parametros del paso indicado; los defaults globales si no esta calibrado
/// (p.ej. los pasos de prueba temporales).
DtwParams paramsFor(String pasoId) => _fitted[pasoId] ?? DtwParams.defaults;

/// Ids con calibracion propia. Util para avisos en herramientas dev.
Iterable<String> get calibratedStepIds => _fitted.keys;
