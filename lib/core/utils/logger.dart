import 'package:flutter/foundation.dart';

/// Logger minimalista. En fases posteriores se puede cambiar por `logging`
/// o `talker` sin tocar los puntos de llamada.
class AppLogger {
  const AppLogger();

  void info(String message) => _log('INFO', message);
  void warn(String message) => _log('WARN', message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) debugPrint('  └─ $error');
    if (stackTrace != null) debugPrint(stackTrace.toString());
  }

  void _log(String level, String message) {
    if (kDebugMode) debugPrint('[$level] $message');
  }
}

const AppLogger logger = AppLogger();
