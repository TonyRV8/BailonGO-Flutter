# Reglas de R8 para el build de release (Play Store).

# MediaPipe Tasks Vision usa protobuf y JNI por reflexión: si R8 renombra o
# quita estas clases, el detector de pose truena en tiempo de ejecución.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }

# AutoValue (dependencia de MediaPipe) referencia el procesador de anotaciones
# de Java, que no existe en Android y nunca se usa en la app.
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**

# Protos de perfilado/plantillas que MediaPipe referencia pero no empaqueta.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

# Flogger (logs internos de MediaPipe) busca su plataforma por nombre con
# Class.forName("...backend.system.DefaultPlatform"): si R8 la renombra, el
# detector de pose truena al crearse ("No logging platforms found").
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**
