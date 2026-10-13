/// Mapeo paso → animación ("action") del maniquí 3D `assets/models/DanceGrid1.glb`.
///
/// El GLB trae 9 animaciones, una por paso WSF Bronce. La pantalla 3D recibe el
/// paso como texto libre (id del catálogo, nombre visible o un alias como
/// "basico" / "right spot turn") y aquí se resuelve a la animación exacta.
class StepAnimations {
  StepAnimations._();

  static const String modelAsset = 'assets/models/DanceGrid1.glb';

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
  /// Los pasos de salsa son una frase de 8 tiempos; si alguna animación se
  /// regraba con otra longitud, se ajusta aquí.
  static const Map<String, int> _beatsPerLoop = {};
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
