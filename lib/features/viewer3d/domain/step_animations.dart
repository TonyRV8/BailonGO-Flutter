/// Mapeo paso → animación ("action") de los personajes 3D ([characters]).
///
/// Cada GLB trae 9 animaciones, una por paso WSF Bronce. La pantalla 3D recibe el
/// paso como texto libre (id del catálogo, nombre visible o un alias como
/// "basico" / "right spot turn") y aquí se resuelve a la animación exacta.
class StepAnimations {
  StepAnimations._();

  static const String modelAsset = 'assets/models/DanceGrid1.glb';

  /// Personajes disponibles; el primero es el que se muestra por defecto.
  static const List<StepCharacter> characters = [
    StepCharacter('Claire', 'assets/models/Claire.glb'),
    StepCharacter('Maniquí', modelAsset),
  ];

  static const String basico = 'basico_3d';
  static const String guapeo = 'guapeo_3d';
  static const String cucaracha = 'cucaracha_3d';
  static const String suzyQ = 'suzyq_3d';
  static const String vuelta = 'vuelta_3d';
  static const String cumbia = 'cumbia_3d';
  static const String cuban = 'cuban_3d';
  static const String toeHeel = 'toeheel_3d';
  static const String kickFlick = 'kickflick_3d';

  /// Nodo del dance grid (cuadrícula de pasos) en la base de la pista.
  static const String danceGridNode = 'salsa_dance_grid';

  /// Todas las animaciones del GLB (el test verifica que existan en el asset).
  static const List<String> all = [
    basico,
    guapeo,
    cucaracha,
    suzyQ,
    vuelta,
    cumbia,
    cuban,
    toeHeel,
    kickFlick,
  ];

  /// Tiempos musicales que dura un ciclo de cada animación. El número que
  /// flota sobre el maniquí avanza cada `duración / tiempos` segundos, así que
  /// basta con esto para que vaya a ritmo (y sigue al slider de velocidad,
  /// porque se calcula sobre el tiempo de la animación, no sobre el reloj).
  /// Los pasos de salsa son una frase de 8 tiempos; los que necesitan dos
  /// frases para cerrar el ciclo (p. ej. la vuelta) duran 16. Sale de
  /// `tool/anim3d/process.py` (campo `beats` de clean.json): si se regeneran
  /// las animaciones, se ajusta aquí.
  static const Map<String, int> _beatsPerLoop = {
    cucaracha: 16,
    vuelta: 16,
    cumbia: 16,
    toeHeel: 16,
    kickFlick: 16,
  };
  static const int defaultBeatsPerLoop = 8;

  static int beatsFor(String animation) =>
      _beatsPerLoop[animation] ?? defaultBeatsPerLoop;

  /// Coincidencia exacta tras normalizar: ids del catálogo y alias conocidos.
  static const Map<String, String> _exact = {
    // Ids de `kCatalogSeed`.
    'basico_adelante_atras': basico,
    'basico_guapeo': guapeo,
    'cucaracha': cucaracha,
    'suzy_q': suzyQ,
    'right_spot_turn': vuelta,
    'cumbia_step': cumbia,
    'cuban_break': cuban,
    'giro_punta_talon': toeHeel,
    'kick_flick': kickFlick,
    // Alias cortos.
    'basico': basico,
    'guapeo': guapeo,
    'suzyq': suzyQ,
    'spot_turn': vuelta,
    'vuelta': vuelta,
    'cumbia': cumbia,
    'cuban': cuban,
    'toe_heel': toeHeel,
    'punta_talon': toeHeel,
    'kickflick': kickFlick,
  };

  /// Respaldo por palabra clave, en orden: "guapeo" va antes que "basico"
  /// porque el nombre visible es "Básico (guapeo)".
  static const List<(String, String)> _keywords = [
    ('guapeo', guapeo),
    ('basic', basico),
    ('cucaracha', cucaracha),
    ('suzy', suzyQ),
    ('spot_turn', vuelta),
    ('vuelta', vuelta),
    ('cumbia', cumbia),
    ('cuban', cuban),
    ('talon', toeHeel),
    ('heel', toeHeel),
    ('kick', kickFlick),
  ];

  /// Animación del paso, o `null` si el paso no tiene versión 3D (p. ej. los
  /// pasos de prueba).
  static String? forStep(String step) {
    final key = normalize(step);
    if (key.isEmpty) return null;
    if (all.contains(key)) return key;
    final exact = _exact[key];
    if (exact != null) return exact;
    for (final (keyword, animation) in _keywords) {
      if (key.contains(keyword)) return animation;
    }
    return null;
  }

  /// "Básico (Guapeo)" → `basico_guapeo`; "right spot turn" → `right_spot_turn`.
  static String normalize(String input) {
    const accents = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', //
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', //
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
      'ñ': 'n',
    };
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(accents[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

/// Personaje que baila en el visor 3D. Cada uno es un GLB con las mismas 9
/// animaciones y la misma pista (ver `tool/anim3d/build.py`).
class StepCharacter {
  const StepCharacter(this.label, this.asset);

  final String label;
  final String asset;
}
