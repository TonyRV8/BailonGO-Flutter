/// Voz guía (conteo + instrucciones) de cada paso, relativa a `assets/` como
/// la espera `AssetSource`. Cada pista está grabada sobre
/// `musica_intento.m4a` desde su segundo 0, que es también el fotograma 0 del
/// video guía: arranca a la vez que la música del intento y que el video de
/// la ficha. Los pasos sin entrada aquí van solo con música.
const Map<String, String> kVoiceGuides = {
  'basico_adelante_atras': 'sounds/audio_guia_basico_adelante_atras.mp3',
  'basico_guapeo': 'sounds/audio_guia_basico_guapeo.mp3',
  'cuban_break': 'sounds/audio_guia_cuban_break.mp3',
  'cucaracha': 'sounds/audio_guia_cucaracha.mp3',
  'cumbia_step': 'sounds/audio_guia_cumbia_step.mp3',
  'giro_punta_talon': 'sounds/audio_guia_giro_punta_talon.mp3',
  'kick_flick': 'sounds/audio_guia_kick_flick.mp3',
  'right_spot_turn': 'sounds/audio_guia_right_spot_turn.mp3',
  'suzy_q': 'sounds/audio_guia_suzy_q.mp3',
};
