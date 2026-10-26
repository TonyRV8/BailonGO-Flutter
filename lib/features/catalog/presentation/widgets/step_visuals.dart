import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/dance_step.dart';
import '../providers/catalog_providers.dart';

/// Piezas visuales que comparten el catálogo y el progreso del perfil.

/// Estado del usuario en un paso según su mejor marca y el umbral de
/// "Aprendido" (RN-02).
enum StepProgress {
  learned('Aprendido', Color(0xFF5FD39A), Color(0xFF003920)),
  practicing('En práctica', Color(0xFFFFA726), Color(0xFF3D2200)),
  notStarted('Nuevo', Color(0x99000000), Colors.white);

  const StepProgress(this.label, this.color, this.onColor);

  final String label;

  /// Color del estado (etiqueta, anillo y barra).
  final Color color;

  /// Texto sobre [color].
  final Color onColor;

  static StepProgress of(double? best, double threshold) {
    if (best == null) return StepProgress.notStarted;
    return best >= threshold ? StepProgress.learned : StepProgress.practicing;
  }
}

/// Frase corta de cada paso para las tarjetas (la descripción completa va en
/// la ficha).
const Map<String, String> kStepTaglines = {
  'basico_adelante_atras': 'Adelante y atrás',
  'basico_guapeo': 'Básico en su lugar',
  'cucaracha': 'Abre a los lados',
  'suzy_q': 'Cruza y abre',
  'right_spot_turn': 'Giro a la derecha',
  'cumbia_step': 'Atrás y medio giro',
  'cuban_break': 'Diagonales',
  'giro_punta_talon': 'Punta, talón y giro',
  'kick_flick': 'Patada y flick',
};

String stepTagline(DanceStep step) {
  final short = kStepTaglines[step.id];
  if (short != null) return short;
  final first = step.descripcion.split(RegExp(r'[.:,]')).first.trim();
  return first.isEmpty ? 'Paso ${step.orden}' : first;
}

/// Fotograma del video de referencia del paso. Las tomas son verticales, así
/// que se encuadra un poco arriba del centro para que entre de la cabeza a
/// los pies. Sin video, el número del paso.
class StepThumbnail extends ConsumerWidget {
  const StepThumbnail({
    super.key,
    required this.step,
    this.alignment = const Alignment(0, -0.3),
  });

  final DanceStep step;

  /// Qué parte de la toma vertical queda a la vista si el recuadro es más
  /// ancho que ella.
  final Alignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    Widget number() => ColoredBox(
          color: scheme.primaryContainer,
          child: Center(
            child: Text('${step.orden}',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(color: scheme.onPrimaryContainer)),
          ),
        );
    if (!step.hasVideo) return number();
    return ref.watch(stepThumbnailProvider(step.mediaUrl!)).maybeWhen(
          data: (bytes) => bytes == null
              ? number()
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  alignment: alignment,
                  gaplessPlayback: true,
                ),
          orElse: () => ColoredBox(color: scheme.surfaceContainerHighest),
        );
  }
}

/// Anillo con la mejor marca del paso, con el porcentaje al centro.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    required this.color,
    this.size = 38,
  });

  final double percent;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            strokeWidth: 3.5,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: Colors.white24,
          ),
          Center(
            child: Text(
              '${percent.round()}%',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.26,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de estado: Aprendido, En práctica o Nuevo.
class StatusTag extends StatelessWidget {
  const StatusTag(this.progress, {super.key});

  final StepProgress progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: progress.color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          progress.label,
          style: TextStyle(
            color: progress.onColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
