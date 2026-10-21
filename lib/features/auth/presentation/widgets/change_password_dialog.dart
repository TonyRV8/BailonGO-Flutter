import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_providers.dart';

/// Diálogo para cambiar la contraseña del usuario con sesión. Pide la actual
/// (Firebase la exige para confirmar que es el dueño de la cuenta), la nueva
/// y su confirmación. Los errores se muestran dentro del diálogo, sin
/// cerrarlo. Devuelve `true` si la contraseña se cambió.
///
/// Los controladores viven en el estado y se liberan en `dispose` (ver
/// EditNameDialog: liberarlos al cerrar rompía la animación de salida).
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => const ChangePasswordDialog(),
      );

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cambiar la contraseña.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
      {String? Function(String?)? validator, bool last = false}) {
    return TextFormField(
      controller: controller,
      obscureText: !_visible,
      enabled: !_loading,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: last ? (_) => _submit() : null,
      decoration: InputDecoration(labelText: label),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_currentCtrl, 'Contraseña actual',
                  validator: Validators.password),
              const SizedBox(height: 8),
              _field(_newCtrl, 'Nueva contraseña',
                  validator: (v) =>
                      Validators.newPassword(v, current: _currentCtrl.text)),
              const SizedBox(height: 8),
              _field(_confirmCtrl, 'Confirmar nueva contraseña',
                  validator: (v) =>
                      Validators.confirmPassword(v, _newCtrl.text),
                  last: true),
              CheckboxListTile(
                value: _visible,
                onChanged: (v) => setState(() => _visible = v ?? false),
                title: const Text('Mostrar contraseñas'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Cambiar'),
        ),
      ],
    );
  }
}
