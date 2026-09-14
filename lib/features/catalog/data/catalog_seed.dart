import '../domain/step_weights.dart';
import 'models/dance_step_model.dart';

/// Catálogo canónico: 9 pasos WSF nivel Bronce (plan.txt §1, doc 5.7) + un paso
/// de prueba. Fuente única de verdad: siembra Firestore y sirve de fallback
/// offline.
///
/// Los videos ideales viven empaquetados en `assets/videos/<pasoId>.mp4`
/// (720x1280, 30 fps, música incluida). De ellos se extraen los landmarks UNA
/// sola vez y se suben a `reference_data` (ver implementar_pasos.txt §6).
///
/// `duracionCicloSeg` es la duración real de la toma, que es exactamente la
/// ventana de evaluación: `evaluation_page._startCapture` la deriva de
/// `refFrames.length * 33 ms`.
const List<DanceStepModel> kCatalogSeed = [
  DanceStepModel(
    id: 'basico_adelante_atras',
    nombre: 'Básico (adelante y atrás)',
    descripcion:
        'Paso base de la cumbia: desplazamiento adelante y atrás manteniendo '
        'el peso en la planta y el ritmo constante.',
    orden: 1,
    mediaUrl: 'assets/videos/basico_adelante_atras.mp4',
    duracionCicloSeg: 19,
    weights: wBasicoAdelanteAtras,
  ),
  DanceStepModel(
    id: 'basico_guapeo',
    nombre: 'Básico (guapeo)',
    descripcion:
        'Variante del básico con acento de cadera y hombros (guapeo), sin '
        'desplazar los pies del eje.',
    orden: 2,
    mediaUrl: 'assets/videos/basico_guapeo.mp4',
    duracionCicloSeg: 14,
    weights: wBasicoGuapeo,
  ),
  DanceStepModel(
    id: 'cucaracha',
    nombre: 'Cucaracha',
    descripcion:
        'Pisada lateral con presión al piso alternando pie izquierdo y '
        'derecho, recuperando el peso al centro.',
    orden: 3,
    mediaUrl: 'assets/videos/cucaracha.mp4',
    duracionCicloSeg: 18,
    weights: wCucaracha,
  ),
  DanceStepModel(
    id: 'suzy_q',
    nombre: 'Suzy Q',
    descripcion:
        'Cruce de talones y puntas desplazándose lateralmente, con giro de '
        'rodillas coordinado.',
    orden: 4,
    mediaUrl: 'assets/videos/suzy_q.mp4',
    duracionCicloSeg: 10,
    weights: wSuzyQ,
  ),
  DanceStepModel(
    id: 'right_spot_turn',
    nombre: 'Right Spot Turn',
    descripcion: 'Giro a la derecha sobre el propio eje en tres tiempos.',
    orden: 5,
    mediaUrl: 'assets/videos/right_spot_turn.mp4',
    duracionCicloSeg: 12,
    weights: wRightSpotTurn,
  ),
  DanceStepModel(
    id: 'cumbia_step',
    nombre: 'Cumbia Step',
    descripcion:
        'Paso característico de cumbia con arrastre lateral y marca de tiempo '
        'en el pie de apoyo.',
    orden: 6,
    mediaUrl: 'assets/videos/cumbia_step.mp4',
    duracionCicloSeg: 19.33,
    weights: wCumbiaStep,
  ),
  DanceStepModel(
    id: 'cuban_break',
    nombre: 'Cuban Break',
    descripcion:
        'Quiebre cubano: cambio de dirección con acento sincopado y juego de '
        'cadera.',
    orden: 7,
    mediaUrl: 'assets/videos/cuban_break.mp4',
    duracionCicloSeg: 14,
    weights: wCubanBreak,
  ),
  DanceStepModel(
    id: 'giro_punta_talon',
    nombre: 'Giro punta-talón',
    descripcion:
        'Giro apoyando alternadamente punta y talón para rotar el cuerpo de '
        'forma controlada.',
    orden: 8,
    mediaUrl: 'assets/videos/giro_punta_talon.mp4',
    duracionCicloSeg: 21,
    weights: wGiroPuntaTalon,
  ),
  DanceStepModel(
    id: 'kick_flick',
    nombre: 'Kick Flick',
    descripcion:
        'Patada baja seguida de un flick (latigazo) del pie, manteniendo el '
        'equilibrio sobre la pierna de apoyo.',
    orden: 9,
    mediaUrl: 'assets/videos/kick_flick.mp4',
    duracionCicloSeg: 13,
    weights: wKickFlick,
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
    weights: armsWeights,
  ),
  // Pasos 11 y 12: copias del paso de prueba para testear la sincronización
  // de la mejor marca (history) por paso. TEMPORALES: quitar junto con
  // paso_prueba al sembrar los pasos reales.
  DanceStepModel(
    id: 'paso_prueba_2',
    nombre: 'Paso de prueba 2 (ref)',
    descripcion:
        'Copia del paso de prueba para testear la sincronización del mejor '
        'intento. Importan brazos, hombros y manos.',
    orden: 11,
    mediaUrl: 'assets/videos/ref.mov',
    duracionCicloSeg: 8,
    weights: armsWeights,
  ),
  DanceStepModel(
    id: 'paso_prueba_3',
    nombre: 'Paso de prueba 3 (ref)',
    descripcion:
        'Copia del paso de prueba para testear la sincronización del mejor '
        'intento. Importan brazos, hombros y manos.',
    orden: 12,
    mediaUrl: 'assets/videos/ref.mov',
    duracionCicloSeg: 8,
    weights: armsWeights,
  ),
];

/// Ids de los pasos de prueba (para dev tools: subir referencia / borrar
/// progreso). TEMPORAL.
const List<String> kTestStepIds = ['paso_prueba', 'paso_prueba_2', 'paso_prueba_3'];

/// Los 9 pasos reales del catálogo (excluye los de prueba). Es lo que usan las
/// herramientas dev de "Subir referencia" y "Calibrar motor".
List<DanceStepModel> get kRealSteps => kCatalogSeed
    .where((s) => !kTestStepIds.contains(s.id))
    .toList(growable: false);

/// Ruta del fixture de la toma "regular" (4-6/10) de un paso, usada solo para
/// calibrar. No se entrega en el APK final (ver .gitignore y pubspec).
String regularFixtureFor(String pasoId) =>
    'assets/fixtures/${pasoId}_regular.mp4';
