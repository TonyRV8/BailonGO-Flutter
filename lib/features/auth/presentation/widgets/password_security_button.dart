import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../providers/auth_providers.dart';
import 'change_password_dialog.dart';

/// Acción de contraseña del perfil. Con contraseña: cambiarla. En cuentas que
/// solo entran con Google no hay contraseña que cambiar: se envía el correo
/// de Firebase para crear una (así también podrán entrar con correo).
class PasswordSecurityButton extends ConsumerWidget {
  const PasswordSecurityButton({super.key, required this.email});

  final String email;

  Future<void> _change(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await ChangePasswordDialog.show(context);
    if (changed == true) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')));
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(email: email);
      messenger.showSnackBar(SnackBar(
          content: Text('Te enviamos un correo a $email para crear tu '
              'contraseña.')));
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo enviar el correo.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPassword = ref.watch(authRepositoryProvider).hasPasswordSignIn;
    return hasPassword
        ? TextButton.icon(
            onPressed: () => _change(context),
            icon: const Icon(Icons.lock_reset),
            label: const Text('Cambiar contraseña'),
          )
        : TextButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.password),
            label: const Text('Crear contraseña'),
          );
  }
}
