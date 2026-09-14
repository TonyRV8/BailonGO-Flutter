import 'package:flutter/material.dart';

import '../../engine/start_gesture_detector.dart';

/// Capa de ayuda durante la fase de armado (RF-08.1..08.5): guía al usuario a
/// encuadrarse y le muestra cómo arrancar la evaluación sin tocar el teléfono.
///
/// A diferencia del conteo, NO ocupa la pantalla: el usuario necesita verse en
/// la preview para colocarse.
class ArmingOverlay extends StatelessWidget {
  const ArmingOverlay({
    super.key,
    required this.status,
    required this.stillnessEnabled,
    required this.onStartNow,
  });

  final ArmingStatus status;

  /// Si el arranque automático por quietud está activo (Configuración).
  final bool stillnessEnabled;

  final VoidCallback onStartNow;

  @override
  Widget build(BuildContext context) {
    final framed = status.state != ArmingState.noBody &&
        status.state != ArmingState.outOfFrame;
    final accent = framed ? const Color(0xFF69F0AE) : const Color(0xFFFFC46B);

    return Positioned.fill(
      child: SafeArea(
        child: Column(
          children: [
            _Banner(status: status, stillnessEnabled: stillnessEnabled, accent: accent),
            const Spacer(),
            if (status.progress > 0)
              _HoldRing(progress: status.progress, accent: accent),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onStartNow,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar ahora'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      backgroundColor: Colors.black45,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.status,
    required this.stillnessEnabled,
    required this.accent,
  });

  final ArmingStatus status;
  final bool stillnessEnabled;
  final Color accent;

  ({IconData icon, String title, String hint}) get _copy {
    switch (status.state) {
      case ArmingState.noBody:
        return (
          icon: Icons.person_search_outlined,
          title: 'Colócate frente a la cámara',
          hint: 'Deja el teléfono apoyado y ponte de frente.',
        );
      case ArmingState.outOfFrame:
        return (
          icon: Icons.zoom_out_map,
          title: 'Aléjate hasta verte completo',
          hint: 'Deben verse caderas, rodillas y pies (~1.4 m).',
        );
      case ArmingState.waiting:
        return (
          icon: Icons.sign_language_outlined,
          title: 'Levanta los brazos para empezar',
          hint: stillnessEnabled
              ? 'O quédate quieto 2 s y empieza solo.'
              : 'Tómate el tiempo que necesites para acomodarte.',
        );
      case ArmingState.raisingArms:
        return (
          icon: Icons.front_hand_outlined,
          title: '¡Así! Mantén los brazos arriba',
          hint: 'No los bajes todavía…',
        );
      case ArmingState.holdingStill:
        return (
          icon: Icons.self_improvement_outlined,
          title: 'Quieto… empezamos',
          hint: 'Muévete si aún no estás listo.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
      ),
      child: Row(
        children: [
          Icon(copy.icon, color: accent, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  copy.hint,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Anillo que "carga" mientras se mantiene el gesto o la quietud: enseña la
/// mecánica sin necesidad de leer instrucciones.
class _HoldRing extends StatelessWidget {
  const _HoldRing({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 10,
              backgroundColor: Colors.black45,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          Text(
            '${(progress * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
