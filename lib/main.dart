import 'package:cloud_firestore/cloud_firestore.dart';
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
    // Offline-first (doc 5.3.3): réplica local persistente sin límite de
    // tamaño; catálogo, referencias, historial y perfil sirven desde cache
    // sin red, y las escrituras pendientes se sincronizan al reconectar.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e, st) {
    // Si ves este error: falta correr `flutterfire configure` para generar
    // las credenciales reales en lib/core/config/firebase_options.dart.
    logger.error('Fallo al inicializar Firebase', e, st);
    rethrow;
  }

  runApp(const ProviderScope(child: BailonGoApp()));
}
