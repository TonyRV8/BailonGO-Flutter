import 'models/dance_step_model.dart';

/// Pesos por feature (22 = 15 tren inferior + 7 tren superior). Cada paso elige
/// qué landmarks importan. Ver `FeatureExtractor` para el orden de las features.
const List<double> _legsWeights = [
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, // 0–14 piernas
  0, 0, 0, 0, 0, 0, 0, //                          15–21 brazos (ignorados)
];
const List<double> _armsWeights = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0–14 piernas (ignoradas)
  1, 1, 1, 1, 1, 1, 1, //                          15–21 brazos
];

/// Catálogo canónico: 9 pasos WSF nivel Bronce (plan.txt §1, doc 5.7) + un paso
/// de prueba. Fuente única de verdad: siembra Firestore y sirve de fallback
/// offline.
///
/// `mediaUrl` queda `null` hasta grabar las 2 tomas por paso (plan.txt §8).
/// Los 9 pasos de cumbia ponderan el tren inferior; el paso de prueba (baile de
/// brazos) pondera el tren superior.
const List<DanceStepModel> kCatalogSeed = [
  DanceStepModel(
    id: 'basico_adelante_atras',
    nombre: 'Básico (adelante y atrás)',
    descripcion:
        'Paso base de la cumbia: desplazamiento adelante y atrás manteniendo '
        'el peso en la planta y el ritmo constante.',
    orden: 1,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'basico_guapeo',
    nombre: 'Básico (guapeo)',
    descripcion:
        'Variante del básico con acento de cadera y hombros (guapeo), sin '
        'desplazar los pies del eje.',
    orden: 2,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'cucaracha',
    nombre: 'Cucaracha',
    descripcion:
        'Pisada lateral con presión al piso alternando pie izquierdo y '
        'derecho, recuperando el peso al centro.',
    orden: 3,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'suzy_q',
    nombre: 'Suzy Q',
    descripcion:
        'Cruce de talones y puntas desplazándose lateralmente, con giro de '
        'rodillas coordinado.',
    orden: 4,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'right_spot_turn',
    nombre: 'Right Spot Turn',
    descripcion: 'Giro a la derecha sobre el propio eje en tres tiempos.',
    orden: 5,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'cumbia_step',
    nombre: 'Cumbia Step',
    descripcion:
        'Paso característico de cumbia con arrastre lateral y marca de tiempo '
        'en el pie de apoyo.',
    orden: 6,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'cuban_break',
    nombre: 'Cuban Break',
    descripcion:
        'Quiebre cubano: cambio de dirección con acento sincopado y juego de '
        'cadera.',
    orden: 7,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'giro_punta_talon',
    nombre: 'Giro punta-talón',
    descripcion:
        'Giro apoyando alternadamente punta y talón para rotar el cuerpo de '
        'forma controlada.',
    orden: 8,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  DanceStepModel(
    id: 'kick_flick',
    nombre: 'Kick Flick',
    descripcion:
        'Patada baja seguida de un flick (latigazo) del pie, manteniendo el '
        'equilibrio sobre la pierna de apoyo.',
    orden: 9,
    duracionCicloSeg: 4,
    weights: _legsWeights,
  ),
  // Paso 10 de PRUEBA: baile de brazos. Usa el video de referencia real
  // (ref.mov) y pondera el tren superior. Valida el pipeline con good/bad.mov.
  DanceStepModel(
    id: 'paso_prueba',
    nombre: 'Paso de prueba (ref)',
    descripcion:
        'Paso de prueba para el pipeline de evaluación. Importan brazos, '
        'hombros y manos; los intentos good/bad deben dar alta/baja precisión.',
    orden: 10,
    mediaUrl: 'assets/videos/ref.mov',
    duracionCicloSeg: 8,
    weights: _armsWeights,
  ),
];
