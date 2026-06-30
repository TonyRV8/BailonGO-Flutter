import 'models/dance_step_model.dart';

/// Catálogo canónico: 9 pasos WSF nivel Bronce (plan.txt §1, doc 5.7).
///
/// Fuente única de verdad. Sirve para:
///   - Sembrar la colección CATALOG en Firestore (seeder dev).
///   - Fallback offline cuando Firestore aún no tiene datos o no hay red.
///
/// `mediaUrl` queda `null` hasta grabar las 2 tomas por paso con la profesora
/// (plan.txt §8, mitiga riesgo R-03). `duracionCicloSeg` es estimación inicial,
/// se calibra al integrar el video real.
const List<DanceStepModel> kCatalogSeed = [
  DanceStepModel(
    id: 'basico_adelante_atras',
    nombre: 'Básico (adelante y atrás)',
    descripcion:
        'Paso base de la cumbia: desplazamiento adelante y atrás manteniendo '
        'el peso en la planta y el ritmo constante.',
    orden: 1,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'basico_guapeo',
    nombre: 'Básico (guapeo)',
    descripcion:
        'Variante del básico con acento de cadera y hombros (guapeo), sin '
        'desplazar los pies del eje.',
    orden: 2,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'cucaracha',
    nombre: 'Cucaracha',
    descripcion:
        'Pisada lateral con presión al piso alternando pie izquierdo y '
        'derecho, recuperando el peso al centro.',
    orden: 3,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'suzy_q',
    nombre: 'Suzy Q',
    descripcion:
        'Cruce de talones y puntas desplazándose lateralmente, con giro de '
        'rodillas coordinado.',
    orden: 4,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'right_spot_turn',
    nombre: 'Right Spot Turn',
    descripcion: 'Giro a la derecha sobre el propio eje en tres tiempos.',
    orden: 5,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'cumbia_step',
    nombre: 'Cumbia Step',
    descripcion:
        'Paso característico de cumbia con arrastre lateral y marca de tiempo '
        'en el pie de apoyo.',
    orden: 6,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'cuban_break',
    nombre: 'Cuban Break',
    descripcion:
        'Quiebre cubano: cambio de dirección con acento sincopado y juego de '
        'cadera.',
    orden: 7,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'giro_punta_talon',
    nombre: 'Giro punta-talón',
    descripcion:
        'Giro apoyando alternadamente punta y talón para rotar el cuerpo de '
        'forma controlada.',
    orden: 8,
    duracionCicloSeg: 4,
  ),
  DanceStepModel(
    id: 'kick_flick',
    nombre: 'Kick Flick',
    descripcion:
        'Patada baja seguida de un flick (latigazo) del pie, manteniendo el '
        'equilibrio sobre la pierna de apoyo.',
    orden: 9,
    duracionCicloSeg: 4,
  ),
  // Paso 10 de PRUEBA: usa el video de referencia real (ref.mov) empaquetado
  // como asset. Sirve para validar reproducción en bucle (RF-07) y, en fases
  // 4-5, la comparación contra good.mov / bad.mov.
  DanceStepModel(
    id: 'paso_prueba',
    nombre: 'Paso de prueba (ref)',
    descripcion:
        'Paso de prueba para el pipeline de evaluación. Reproduce el video de '
        'referencia real; los intentos good/bad deben dar precisión alta/baja.',
    orden: 10,
    mediaUrl: 'assets/videos/ref.mov',
    duracionCicloSeg: 8,
  ),
];
