import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_options.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    // Si ves este error: falta correr `flutterfire configure` para generar
    // las credenciales reales en lib/core/config/firebase_options.dart.
    logger.error('Fallo al inicializar Firebase', e, st);
    rethrow;
  }

  runApp(const ProviderScope(child: BailonGoApp()));
}
