import 'package:flutter/material.dart';

/// Diálogo para cambiar el nombre del perfil. Devuelve el nombre sin espacios
/// de sobra, o `null` si se cancela (botón, tocar fuera o atrás).
///
/// El controlador del texto vive en el estado del diálogo y se libera en su
/// `dispose`, cuando el diálogo ya terminó su animación de salida. Liberarlo
/// justo después de `showDialog` (como antes) lo destruía mientras el
/// TextField aún se dibujaba y salía la pantalla roja "_dependents.isEmpty".
class EditNameDialog extends StatefulWidget {
  const EditNameDialog({super.key, required this.initial});

  final String initial;

  static Future<String?> show(BuildContext context,
          {required String initial}) =>
      showDialog<String>(
        context: context,
        builder: (_) => EditNameDialog(initial: initial),
      );

  @override
  State<EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar nombre'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(labelText: 'Nombre'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
