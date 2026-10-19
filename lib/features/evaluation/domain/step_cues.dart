/// "Filtro" de flechas de cada paso: qué flecha sale y en qué segundo del
/// intento, copiado de "Señales de baile · 9 pasos autorizados"
/// (`Pasos_Baile_9_Autorizados.docx`) sin las señales de REGRESA y con las
/// figuras rápidas juntas en una sola señal (ver los comentarios de cada paso).
///
/// No se calcula nada en vivo: la pista de señales es fija por paso, igual que
/// la coreografía del video guía, y el overlay sólo la dibuja siguiendo el
/// reloj de la captura (que arranca en el "¡YA!", el mismo instante en que
/// empieza el video y la música).
///
/// CÓMO EDITARLO
///   Cada fila del documento es `StepCue(Ejecutar, Flecha, Indicación)`, en
///   SEGUNDOS desde el "¡YA!". La flecha aparece [kCueLeadMs] antes de
///   Ejecutar (la columna "Mostrar") y se queda hasta que aparece la
///   siguiente, con un máximo de [kCueHoldMs] después de Ejecutar.
///
///   DER/IZQ son del cuerpo de la bailarina, no de la pantalla. La preview de
///   la cámara frontal va en espejo, así que coinciden: si te mueves a tu
///   izquierda, tu imagen va hacia el lado izquierdo de la pantalla. Con
///   cámara trasera el overlay voltea la flecha (el texto no cambia).
library;

/// Flechas del documento.
enum CueDir {
  forward('↑'),
  back('↓'),
  right('→'),
  left('←'),
  upLeft('↖'),
  upRight('↗'),
  downRight('↘'),
  downLeft('↙'),
  turnLeft('↺'),
  turnRight('↻'),

  /// CIERRA.
  close('•');

  const CueDir(this.symbol);

  /// Símbolo de la columna "Flecha".
  final String symbol;

  static CueDir? fromSymbol(String symbol) {
    for (final d in values) {
      if (d.symbol == symbol) return d;
    }
    return null;
  }
}

/// Una fila del documento: a los [t] segundos ("Ejecutar") hacer [label]
/// ("Indicación") con la flecha [arrow].
class StepCue {
  const StepCue(this.t, this.arrow, this.label, {this.fin});

  final double t;

  /// Símbolo de la columna "Flecha" (ver [CueDir]).
  final String arrow;

  /// Texto en pantalla.
  final String label;

  /// Cuándo deja de mostrarse; lo resuelve [cuesFor].
  final double? fin;

  CueDir get dir => CueDir.fromSymbol(arrow)!;

  int get tMs => (t * 1000).round();
  int get showMs => tMs - kCueLeadMs;
  int get endMs => fin != null ? (fin! * 1000).round() : tMs + kCueHoldMs;
}

/// Cuánto antes del tiempo marcado aparece la flecha (Mostrar = Ejecutar − 0.40).
const int kCueLeadMs = 400;

/// Máximo que sigue en pantalla una señal después de su tiempo.
const int kCueHoldMs = 1000;

/// Pista de señales por paso.
const Map<String, List<StepCue>> kStepCues = {
  'basico_adelante_atras': [
    StepCue(0.75, '↑', 'ADEL DER'),
    StepCue(2.30, '↓', 'ATRÁS IZQ'),
    StepCue(3.85, '↑', 'ADEL DER'),
    StepCue(5.45, '↓', 'ATRÁS IZQ'),
    StepCue(7.05, '↑', 'ADEL DER'),
    StepCue(8.65, '↓', 'ATRÁS IZQ'),
    StepCue(10.25, '↑', 'ADEL DER'),
    StepCue(11.85, '↓', 'ATRÁS IZQ'),
    StepCue(13.45, '↑', 'ADEL DER'),
    StepCue(15.05, '↓', 'ATRÁS IZQ'),
    StepCue(16.65, '↑', 'ADEL DER'),
    StepCue(18.35, '•', 'CIERRA'),
  ],
  'cuban_break': [
    StepCue(0.80, '↑', 'ADEL DER'),
    StepCue(2.14, '↓', 'ATRÁS IZQ'),
    StepCue(3.15, '↖', 'DIAG IZQ'),
    StepCue(3.65, '↓', 'ATRÁS'),
    StepCue(4.62, '↗', 'DIAG DER'),
    StepCue(5.10, '↓', 'ATRÁS'),
    StepCue(6.04, '↖', 'DIAG IZQ'),
    StepCue(6.51, '↓', 'ATRÁS'),
    StepCue(7.45, '↗', 'DIAG DER'),
    StepCue(7.93, '↓', 'ATRÁS'),
    StepCue(8.86, '↖', 'DIAG IZQ'),
    StepCue(9.34, '↓', 'ATRÁS'),
    StepCue(10.31, '↗', 'DIAG DER'),
    StepCue(10.78, '↓', 'ATRÁS'),
    StepCue(11.74, '↖', 'DIAG IZQ'),
    StepCue(12.76, '↗', 'DIAG DER'),
    StepCue(13.78, '•', 'CIERRA'),
  ],
  'cucaracha': [
    StepCue(0.85, '↑', 'ADELANTE'),
    StepCue(2.20, '↓', 'ATRÁS'),
    StepCue(3.60, '→', 'DERECHA'),
    StepCue(5.15, '←', 'IZQUIERDA'),
    StepCue(6.90, '↑', 'ADELANTE'),
    StepCue(8.35, '↓', 'ATRÁS'),
    StepCue(9.35, '→', 'DERECHA'),
    StepCue(10.80, '←', 'IZQUIERDA'),
    StepCue(12.20, '↑', 'ADELANTE'),
    StepCue(13.45, '↓', 'ATRÁS'),
    StepCue(14.80, '→', 'DERECHA'),
    StepCue(16.15, '←', 'IZQUIERDA'),
  ],
  // Adelante, atrás y luego MEDIO GIRO y ATRÁS alternados: donde el documento
  // ponía dos ATRÁS entre giros se quitó el primero (el que va justo después
  // del giro).
  'cumbia_step': [
    StepCue(0.70, '↑', 'ADELANTE'),
    StepCue(1.95, '↓', 'ATRÁS'),
    StepCue(2.85, '↺', 'MEDIO GIRO IZQ'),
    StepCue(4.75, '↓', 'ATRÁS'),
    StepCue(5.25, '↻', 'MEDIO GIRO DER'),
    StepCue(7.10, '↓', 'ATRÁS'),
    StepCue(7.65, '↺', 'MEDIO GIRO IZQ'),
    StepCue(8.45, '↓', 'ATRÁS'),
    StepCue(9.05, '↺', 'MEDIO GIRO IZQ'),
    StepCue(9.70, '↓', 'ATRÁS'),
    StepCue(10.55, '↻', 'MEDIO GIRO DER'),
    StepCue(12.55, '↓', 'ATRÁS'),
    StepCue(13.15, '↺', 'MEDIO GIRO IZQ'),
    StepCue(15.15, '↓', 'ATRÁS'),
    StepCue(15.65, '↺', 'MEDIO GIRO IZQ'),
    StepCue(17.65, '↓', 'ATRÁS'),
    StepCue(18.85, '•', 'CIERRA'),
  ],
  // PUNTA y TALÓN del mismo pie en una sola señal.
  'giro_punta_talon': [
    StepCue(0.85, '↑', 'ADEL DER'),
    StepCue(2.15, '↓', 'ATRÁS IZQ'),
    StepCue(3.50, '↘', 'PUNTA TALÓN DER'),
    StepCue(4.35, '↺', 'MEDIO GIRO IZQ'),
    StepCue(5.55, '↙', 'PUNTA TALÓN IZQ'),
    StepCue(6.40, '↻', 'MEDIO GIRO DER'),
    StepCue(7.40, '↑', 'ADEL DER'),
    StepCue(8.75, '↓', 'ATRÁS IZQ'),
    StepCue(10.15, '↘', 'PUNTA TALÓN DER'),
    StepCue(10.85, '↺', 'MEDIO GIRO IZQ'),
    StepCue(11.90, '↙', 'PUNTA TALÓN IZQ'),
    StepCue(12.75, '↻', 'MEDIO GIRO DER'),
    StepCue(13.50, '↑', 'ADEL DER'),
    StepCue(14.90, '↓', 'ATRÁS IZQ'),
    StepCue(16.45, '↘', 'PUNTA TALÓN DER'),
    StepCue(17.15, '↺', 'MEDIO GIRO IZQ'),
    StepCue(18.20, '↙', 'PUNTA TALÓN IZQ'),
    StepCue(19.10, '↻', 'MEDIO GIRO DER'),
    StepCue(20.30, '•', 'CIERRA'),
  ],
  'basico_guapeo': [
    StepCue(0.90, '↑', 'ADEL DER'),
    StepCue(2.80, '↓', 'ATRÁS IZQ'),
    StepCue(4.50, '↑', 'ADEL DER'),
    StepCue(5.80, '↓', 'ATRÁS IZQ'),
    StepCue(7.30, '↑', 'ADEL DER'),
    StepCue(9.00, '↓', 'ATRÁS IZQ'),
    StepCue(10.50, '↑', 'ADEL DER'),
    StepCue(11.90, '↓', 'ATRÁS IZQ'),
    StepCue(13.65, '•', 'CIERRA'),
  ],
  // Cada bloque CUARTO GIRO + PATADA + FLICK + ATRÁS es una sola PATADA hacia
  // el lado al que gira el cuerpo.
  'kick_flick': [
    StepCue(0.80, '↑', 'ADEL DER'),
    StepCue(1.85, '↓', 'ATRÁS IZQ'),
    StepCue(2.70, '←', 'PATADA IZQ'),
    StepCue(4.65, '→', 'PATADA DER'),
    StepCue(6.45, '↑', 'ADEL DER'),
    StepCue(7.60, '↓', 'ATRÁS IZQ'),
    StepCue(8.50, '←', 'PATADA IZQ'),
    StepCue(10.50, '→', 'PATADA DER'),
    StepCue(12.25, '•', 'CIERRA'),
  ],
  'right_spot_turn': [
    StepCue(0.75, '↑', 'ADEL DER'),
    StepCue(2.20, '↓', 'ATRÁS IZQ'),
    StepCue(3.15, '↑', 'ADEL DER'),
    StepCue(3.55, '↻', 'GIRO DER HACIA ATRÁS'),
    StepCue(5.85, '↑', 'ADEL DER'),
    StepCue(7.25, '↓', 'ATRÁS IZQ'),
    StepCue(8.65, '↑', 'ADEL DER'),
    StepCue(9.05, '↻', 'GIRO DER HACIA ATRÁS'),
    StepCue(11.65, '•', 'CIERRA'),
  ],
  'suzy_q': [
    StepCue(0.80, '↘', 'CRUZA IZQ FRENTE'),
    StepCue(1.35, '→', 'ABRE DER'),
    StepCue(1.85, '↙', 'CRUZA DER FRENTE'),
    StepCue(2.35, '←', 'ABRE IZQ'),
    StepCue(2.85, '↘', 'CRUZA IZQ FRENTE'),
    StepCue(3.35, '→', 'ABRE DER'),
    StepCue(3.85, '↙', 'CRUZA DER FRENTE'),
    StepCue(4.35, '←', 'ABRE IZQ'),
    StepCue(4.85, '↘', 'CRUZA IZQ FRENTE'),
    StepCue(5.35, '→', 'ABRE DER'),
    StepCue(5.85, '↙', 'CRUZA DER FRENTE'),
    StepCue(6.35, '←', 'ABRE IZQ'),
    StepCue(6.85, '↘', 'CRUZA IZQ FRENTE'),
    StepCue(7.35, '→', 'ABRE DER'),
    StepCue(7.85, '↙', 'CRUZA DER FRENTE'),
    StepCue(8.35, '←', 'ABRE IZQ'),
    StepCue(9.40, '•', 'CIERRA'),
  ],
};

final Map<String, List<StepCue>> _resolved = {};

/// Señales del paso con su fin resuelto (cada una se quita cuando aparece la
/// siguiente), vacío si todavía no tiene pista (pasos de prueba).
List<StepCue> cuesFor(String pasoId) => _resolved.putIfAbsent(pasoId, () {
      final raw = kStepCues[pasoId] ?? const <StepCue>[];
      return [
        for (var i = 0; i < raw.length; i++)
          i + 1 < raw.length && raw[i].endMs > raw[i + 1].showMs
              ? StepCue(raw[i].t, raw[i].arrow, raw[i].label,
                  fin: raw[i + 1].showMs / 1000)
              : raw[i],
      ];
    });
