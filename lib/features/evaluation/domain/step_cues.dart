/// "Filtro" de flechas de cada paso: qué flecha sale y en qué segundo del
/// intento, escrito a mano viendo el video de referencia.
///
/// No se calcula nada en vivo: la pista de señales es fija por paso, igual que
/// la coreografía del video guía, y el overlay sólo la dibuja siguiendo el
/// reloj de la captura (que arranca en el "¡YA!", el mismo instante en que
/// empieza el video y la música).
///
/// CÓMO EDITARLO
///   El tiempo va en SEGUNDOS desde el "¡YA!". Para una pista regular (la
///   mayoría de los pasos repiten la misma figura cada dos tiempos) está
///   [cycle]; para una señal suelta se escribe `StepCue(4.5, CueDir.turnRight)`.
///   La flecha aparece [kCueLeadMs] antes del tiempo indicado, para que dé
///   tiempo a reaccionar, y se apaga al terminar su duración.
///
///   Las direcciones son las del BAILARÍN ("tu izquierda"), no las de la
///   pantalla. La preview de la cámara frontal va en espejo, así que coinciden:
///   si te mueves a tu izquierda, tu imagen va hacia el lado izquierdo de la
///   pantalla. Con cámara trasera el overlay las invierte solo.
library;

/// Hacia dónde debe moverse el usuario.
enum CueDir {
  left,
  right,
  forward,
  back,
  turnRight,
  turnLeft,

  /// Pie arriba: patada, flick, punta.
  up,
}

/// Una señal: a los [t] segundos del intento, moverse hacia [dir] durante
/// [dur] segundos.
class StepCue {
  const StepCue(this.t, this.dir, {this.dur = 0.8});

  final double t;
  final CueDir dir;
  final double dur;

  int get tMs => (t * 1000).round();
  int get durMs => (dur * 1000).round();
  int get endMs => tMs + durMs;
}

/// Cuánto antes del tiempo marcado aparece la flecha.
const int kCueLeadMs = 400;

/// Pista regular: [count] señales desde [start], una cada [period] segundos,
/// alternando [dirs] en orden.
List<StepCue> cycle({
  required double start,
  required double period,
  required int count,
  required List<CueDir> dirs,
  double dur = 0.8,
}) =>
    [
      for (var i = 0; i < count; i++)
        StepCue(start + i * period, dirs[i % dirs.length], dur: dur),
    ];

/// Pista de señales por paso. BORRADOR regular: hay que ajustar los segundos
/// viendo cada video, que es el único trabajo manual de esta función.
final Map<String, List<StepCue>> kStepCues = {
  // 19 s: adelante y atrás alternando.
  'basico_adelante_atras': cycle(
    start: 1,
    period: 2,
    count: 9,
    dirs: [CueDir.forward, CueDir.back],
  ),
  // 14 s: el guapeo no desplaza los pies; la señal marca el acento de cadera
  // a cada lado.
  'basico_guapeo': cycle(
    start: 1,
    period: 2,
    count: 6,
    dirs: [CueDir.left, CueDir.right],
  ),
  // 18 s: pisada lateral alternando.
  'cucaracha': cycle(
    start: 1,
    period: 2,
    count: 8,
    dirs: [CueDir.left, CueDir.right],
  ),
  // 10 s: cruces desplazándose de lado.
  'suzy_q': cycle(
    start: 1,
    period: 2,
    count: 4,
    dirs: [CueDir.right, CueDir.left],
  ),
  // 12 s: giro a la derecha sobre el eje.
  'right_spot_turn': cycle(
    start: 1.5,
    period: 4,
    count: 3,
    dirs: [CueDir.turnRight],
    dur: 1.6,
  ),
  // 19.33 s: arrastre lateral.
  'cumbia_step': cycle(
    start: 1,
    period: 2,
    count: 9,
    dirs: [CueDir.left, CueDir.right],
  ),
  // 14 s: quiebre con cambio de dirección.
  'cuban_break': cycle(
    start: 1,
    period: 2,
    count: 6,
    dirs: [CueDir.forward, CueDir.back],
  ),
  // 21 s: rota a un lado y vuelve.
  'giro_punta_talon': cycle(
    start: 1.5,
    period: 3,
    count: 6,
    dirs: [CueDir.turnRight, CueDir.turnLeft],
    dur: 1.2,
  ),
  // 13 s: patada baja alternando pierna.
  'kick_flick': cycle(
    start: 1,
    period: 2,
    count: 6,
    dirs: [CueDir.up],
  ),
};

/// Señales del paso, vacío si todavía no tiene pista (pasos de prueba).
List<StepCue> cuesFor(String pasoId) => kStepCues[pasoId] ?? const [];
