# BailonGO (Flutter)

App de aprendizaje y evaluación de pasos de baile (WSF Bronce) con visión por
computadora. Migración del prototipo Android/Kotlin a Flutter multiplataforma,
offline-first, backend Firebase. Ver `plan.txt` y `BailonGO_TT1_DOCUMENTACIÓN.pdf`.

## Estado: FASE 1 — Cimientos

Implementado:
- Proyecto Flutter + dependencias (Firebase, Riverpod, go_router).
- Tema Material 3 (`lib/core/theme`).
- Navegación con go_router + Drawer persistente (RF-01): Catálogo / Perfil / Configuración.
- Módulo Auth completo (email/contraseña): login, registro, logout, guardas de
  ruta y persistencia de sesión (Clean Architecture: data/domain/presentation).
- Entidad `AppUser` + repositorio + providers Riverpod.

Pendiente (fases 2–8): catálogo, módulo de pose (MediaPipe), motor de evaluación
(DTW), flujo end-to-end, progreso, sincronización offline.

## Arquitectura

```
lib/
  main.dart            # bootstrap Firebase + ProviderScope
  app.dart             # MaterialApp.router
  core/
    config/            # constantes + firebase_options (generado)
    theme/             # Material 3
    router/            # go_router, guardas, shell del drawer, splash
    error/             # Failure / Exception
    utils/             # logger, validators
  features/
    auth/{data,domain,presentation}/
    catalog/  profile/  settings/   # placeholders (se llenan por fase)
```

## Puesta en marcha (pasos manuales)

Requiere Flutter SDK instalado (`flutter --version`).

1. **Generar scaffolding nativo** (android/ios/web) sin perder `lib/`:
   ```bash
   cd C:/BailonGO
   flutter create . --org com.bailongo --project-name bailongo
   ```

2. **Instalar dependencias:**
   ```bash
   flutter pub get
   ```

3. **Crear el proyecto Firebase** en https://console.firebase.google.com
   y añadir apps Android/iOS (o dejar que el paso 4 lo configure).

4. **Conectar Firebase** (genera `lib/core/config/firebase_options.dart` real,
   reemplazando el placeholder):
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<TU_PROJECT_ID>
   ```

5. **Habilitar Authentication** en la consola Firebase →
   Authentication → Sign-in method → **Email/Password** (Activar).

6. **Crear Firestore** (modo producción) y publicar las reglas de
   `firestore.rules`.

7. **Ejecutar:**
   ```bash
   flutter run
   ```

> Mientras `firebase_options.dart` siga siendo el placeholder,
> `Firebase.initializeApp` lanzará `UnsupportedError` (es la señal de que
> falta el paso 4).
