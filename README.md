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

## Puesta en marcha

> **Guía completa paso a paso: [`GUIA_INSTALACION.pdf`](GUIA_INSTALACION.pdf)**
> Instalación desde cero (Flutter, Android Studio, SDK de Android), clonado,
> ejecución y solución de problemas. Léela si es tu primera vez con el proyecto.

Versión corta, si ya tienes Flutter 3.44.4 y Android Studio configurados:

```bash
git clone https://github.com/TonyRV8/BailonGO-Flutter.git
cd BailonGO-Flutter
flutter pub get
flutter run          # con un celular Android (API 24+) conectado por USB
```

**No hace falta configurar Firebase.** Las credenciales de cliente ya están
versionadas en `android/app/google-services.json` y en
`lib/core/config/firebase_options.dart`; todo el equipo usa el mismo proyecto
`bailongo-f3384`. El acceso a los datos lo protegen `firestore.rules` y
`storage.rules`, no esos archivos.

### No corras estos comandos

| Comando | Por qué |
|---|---|
| `flutter create .` | Regenera `android/`, `ios/` y `web/` y **borra** los cambios hechos a mano: permiso de cámara, `minSdk 24`, `noCompress("task")` y la dependencia de MediaPipe. |
| `flutterfire configure` | Sobrescribe `firebase_options.dart` con otro proyecto y el equipo deja de compartir la base de datos. |
| `flutter upgrade` | El proyecto está fijado a Flutter 3.44.4. Avisa al equipo antes de subir de versión. |

### Reglas de seguridad del backend

Se publican una sola vez desde la consola de Firebase (ya están aplicadas):
`firestore.rules` en Firestore -> Rules y `storage.rules` en Storage -> Rules.
