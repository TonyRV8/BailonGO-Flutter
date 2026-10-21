import 'package:flutter/material.dart';

/// Botón "Continuar con Google" (login y registro).
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Text(
        'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4285F4),
        ),
      ),
      label: const Text('Continuar con Google'),
    );
  }
}
