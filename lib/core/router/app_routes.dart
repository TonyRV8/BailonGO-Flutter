/// Rutas declarativas de la app (paths centralizados).
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';

  // Secciones del drawer (RF-01).
  static const String catalog = '/catalog';
  static const String profile = '/profile';
  static const String settings = '/settings';

  // Ficha de paso (RF-06): se usa como `$step/$pasoId`. Fuera del shell del
  // drawer (pantalla propia con AppBar y botón atrás).
  static const String step = '/step';

  // Cámara / pose (RF-09, Fase 3): `$pose/$pasoId`.
  static const String pose = '/pose';

  // Evaluación end-to-end (RF-08..11, Fase 5): `$evaluate/$pasoId`.
  static const String evaluate = '/evaluate';

  /// Ruta inicial tras iniciar sesión.
  static const String home = catalog;
}
