// Pesos por feature de cada paso.
//
// Vive en domain/ y NO depende de Firebase a propósito: así el banco de
// calibración (`tool/calibrate.dart`) puede importarlo con `dart run` sin
// arrastrar cloud_firestore al grafo.
//
// ─────────────────────────────────────────────────────────────────────────────
// PESOS POR FEATURE (26 = 15 tren inferior + 7 tren superior + 4 de cadera)
//
// Cada paso decide qué landmarks importan. El orden de las features está en
// `FeatureExtractor`; el peso se aplica en `DtwComparator._normalizedEuclideanDist`,
// que normaliza dividiendo por la suma de pesos (no hace falta que sumen 1).
// Peso 0 = la feature se ignora por completo en el coste.
//
//   0,1   ángulo de rodilla L/R          11,12  dirección X del pie L/R
//   2,3   inclinación de pierna L/R      13,14  pitch del pie L/R
//   4     distancia entre tobillos       15,16  ángulo de brazo L/R
//   5,6   altura Y del tobillo L/R       17     inclinación de hombros
//   7,8   X del tobillo L/R              18,19  X de muñeca L/R
//   9,10  X de rodilla L/R               20,21  Y de muñeca L/R
//   22    inclinación de cadera          24     altura de cadera
//   23    desplazamiento lateral cadera  25     rotación de cadera
//
// JERARQUÍA (indicada por el usuario, 2026-09-13): en los 9 pasos de salsa
// manda el TREN INFERIOR, después los HOMBROS y por último MANOS/BRAZOS. El
// paso de prueba antiguo ponderaba los brazos porque era un baile de brazos;
// esos pesos ya no aplican aquí.
//   tren inferior (0-14) ...... 0.3 a 3.0 según el paso
//   cadera (22-25) ............ 1.0 a 2.0 — es tren inferior, pesa alto
//   hombros (17) .............. 0.5 base; 1.5 en guapeo, 0.8 en cuban break
//   brazos y manos (15,16,18-21) 0.25 — cuentan, pero no mandan: la posición
//                                de brazos varía entre tomas sin ser un error
//
// CADERA: ya se mide (features 22-25), derivadas de los DOS landmarks de
// cadera (23 izquierda y 24 derecha). Ver `FeatureExtractor._hipFeatures`.
//
// AVISO: la ponderación relativa dentro del tren inferior es un PUNTO DE
// PARTIDA razonado por biomecánica, no un valor medido. Se comprobó que mueve
// poco la aguja (§7-bis paso 3). Lo que sí está calibrado contra datos son los
// rangos por feature (`DtwParams.defaultFeatureRanges`) y los umbrales por
// paso (`step_params.dart`).
// ─────────────────────────────────────────────────────────────────────────────

/// Tren superior puro: para el paso de prueba antiguo (baile de brazos).
const List<double> armsWeights = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0–14 piernas (ignoradas)
  1, 1, 1, 1, 1, 1, 1, //                          15–21 brazos
  0, 0, 0, 0, // 22-25 cadera ignorada (baile de brazos)
];

/// Básico adelante/atrás: el desplazamiento es en profundidad, que en vista
/// frontal 2D casi no genera señal en X. Lo que sí cambia es la flexión de
/// rodilla, la inclinación de pierna y la altura aparente del tobillo.
const List<double> wBasicoAdelanteAtras = [
  1.5, 1.5, // 0,1   rodillas: marcan el paso
  1.5, 1.5, // 2,3   inclinación de pierna
  1.5, //      4     distancia entre pies
  1.5, 1.5, // 5,6   altura del tobillo (proxy de profundidad)
  0.5, 0.5, // 7,8   X tobillo: poco desplazamiento lateral
  0.5, 0.5, // 9,10  X rodilla
  1.0, 1.0, // 11,12 dirección del pie
  1.0, 1.0, // 13,14 pitch del pie
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.0, 1.5, 1.0, 1.0, // 22-25 cadera: acompaña, no es la firma
];

/// Básico con guapeo: mismo eje de pies, pero con acento de cadera y hombros.
/// Es el paso donde el tren superior aporta más señal.
const List<double> wBasicoGuapeo = [
  1.2, 1.2, // 0,1   rodillas
  1.2, 1.2, // 2,3   inclinación de pierna
  1.0, //      4
  1.0, 1.0, // 5,6
  0.5, 0.5, // 7,8   los pies no salen del eje
  0.8, 0.8, // 9,10  las rodillas sí acompañan la cadera
  0.8, 0.8, // 11,12
  0.8, 0.8, // 13,14
  0.25, 0.25, // 15,16 brazos
  1.5, //      17    inclinación de hombros: EL acento del guapeo
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.5, 2.0, 1.0, 1.5, // 22-25 cadera: EL acento del guapeo
];

/// Cucaracha: pisada lateral con presión al piso. La firma es cuánto se abre
/// el compás y hacia dónde va el peso.
const List<double> wCucaracha = [
  1.0, 1.0, // 0,1
  1.2, 1.2, // 2,3   inclinación: el cuerpo carga a un lado
  2.5, //      4     distancia entre tobillos: LA señal
  1.0, 1.0, // 5,6
  2.0, 2.0, // 7,8   X del tobillo: lateralidad
  1.5, 1.5, // 9,10  X de rodilla
  0.8, 0.8, // 11,12
  1.0, 1.0, // 13,14 pitch: la presión al piso
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.5, 2.0, 1.0, 1.0, // 22-25 cadera: el peso carga a un lado
];

/// Suzy Q: cruce de talones y puntas. Todo está en la orientación del pie.
const List<double> wSuzyQ = [
  0.8, 0.8, // 0,1   la rodilla flexiona poco
  1.0, 1.0, // 2,3
  1.5, //      4
  0.8, 0.8, // 5,6
  1.0, 1.0, // 7,8   desplazamiento lateral
  1.2, 1.2, // 9,10  giro de rodillas coordinado
  2.5, 2.5, // 11,12 dirección del pie: LA firma del paso
  2.5, 2.5, // 13,14 pitch talón/punta: LA firma del paso
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.0, 1.2, 1.0, 1.0, // 22-25 cadera: acompaña el cruce
];

/// Right Spot Turn: giro sobre el propio eje. Durante la rotación las
/// posiciones X de tobillo y rodilla son ruidosas (el cuerpo rota, no se
/// desplaza), así que se bajan mucho para no castigar un giro correcto.
const List<double> wRightSpotTurn = [
  0.8, 0.8, // 0,1
  1.0, 1.0, // 2,3
  1.0, //      4
  1.0, 1.0, // 5,6
  0.3, 0.3, // 7,8   X tobillo: ruido de rotación
  0.3, 0.3, // 9,10  X rodilla: ruido de rotación
  2.0, 2.0, // 11,12 dirección del pie: sigue el giro
  1.5, 1.5, // 13,14 pitch: pivote
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.0, 1.0, 1.0, 2.0, // 22-25 cadera: la rotación es la señal
];

/// Cumbia Step: arrastre lateral con marca de tiempo en el pie de apoyo.
const List<double> wCumbiaStep = [
  1.0, 1.0, // 0,1
  1.2, 1.2, // 2,3
  2.0, //      4     apertura del compás en el arrastre
  1.0, 1.0, // 5,6
  1.5, 1.5, // 7,8   lateralidad
  1.0, 1.0, // 9,10
  1.0, 1.0, // 11,12
  1.5, 1.5, // 13,14 pitch: la marca de tiempo del pie de apoyo
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.5, 1.8, 1.0, 1.0, // 22-25 cadera: acompaña el arrastre
];

/// Cuban Break: quiebre con cambio de dirección, acento sincopado y cadera.
const List<double> wCubanBreak = [
  1.5, 1.5, // 0,1   el quiebre es de rodilla
  1.5, 1.5, // 2,3   inclinación: el cambio de dirección
  1.5, //      4
  1.0, 1.0, // 5,6
  1.5, 1.5, // 7,8
  1.2, 1.2, // 9,10  juego de cadera vía rodillas
  0.8, 0.8, // 11,12
  1.0, 1.0, // 13,14
  0.25, 0.25, // 15,16 brazos
  0.8, //      17    el hombro acompaña el acento sincopado
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.5, 2.0, 1.0, 1.5, // 22-25 cadera: el juego de cadera del quiebre
];

/// Giro punta-talón: rotación apoyando punta y talón alternadamente. Igual que
/// el Right Spot Turn, la X es ruido; la orientación del pie lo es todo.
const List<double> wGiroPuntaTalon = [
  0.8, 0.8, // 0,1
  1.0, 1.0, // 2,3
  1.0, //      4
  1.0, 1.0, // 5,6
  0.3, 0.3, // 7,8   ruido de rotación
  0.3, 0.3, // 9,10  ruido de rotación
  2.5, 2.5, // 11,12 dirección del pie: LA firma
  2.5, 2.5, // 13,14 pitch punta/talón: LA firma
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.0, 1.0, 1.0, 2.0, // 22-25 cadera: la rotación es la señal
];

/// Kick Flick: patada baja + latigazo. La altura del tobillo es la señal
/// dominante, seguida de la extensión de rodilla.
const List<double> wKickFlick = [
  2.0, 2.0, // 0,1   extensión de rodilla en la patada
  1.5, 1.5, // 2,3
  1.0, //      4
  3.0, 3.0, // 5,6   altura del tobillo: LA señal del paso
  0.8, 0.8, // 7,8
  0.8, 0.8, // 9,10
  1.0, 1.0, // 11,12
  1.5, 1.5, // 13,14 pitch: el flick
  0.25, 0.25, // 15,16 brazos
  0.5, //      17    hombros
  0.25, 0.25, 0.25, 0.25, // 18–21 manos
  1.0, 1.0, 1.2, 1.0, // 22-25 cadera: estabiliza en la patada
];

/// Pesos por `pasoId`. Fuente única para el catálogo y para el banco de
/// calibración.
const Map<String, List<double>> kStepWeights = {
  'basico_adelante_atras': wBasicoAdelanteAtras,
  'basico_guapeo': wBasicoGuapeo,
  'cucaracha': wCucaracha,
  'suzy_q': wSuzyQ,
  'right_spot_turn': wRightSpotTurn,
  'cumbia_step': wCumbiaStep,
  'cuban_break': wCubanBreak,
  'giro_punta_talon': wGiroPuntaTalon,
  'kick_flick': wKickFlick,
};

/// Orden canónico de los 9 pasos reales (= campo `orden` del catálogo).
const List<String> kRealStepIds = [
  'basico_adelante_atras',
  'basico_guapeo',
  'cucaracha',
  'suzy_q',
  'right_spot_turn',
  'cumbia_step',
  'cuban_break',
  'giro_punta_talon',
  'kick_flick',
];
