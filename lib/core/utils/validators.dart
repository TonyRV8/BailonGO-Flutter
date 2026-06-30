/// Validadores reutilizables para formularios.
class Validators {
  Validators._();

  static final _emailRegex = RegExp(r'^[\w.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo.';
    if (!_emailRegex.hasMatch(v)) return 'Correo no válido.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresa tu contraseña.';
    if (v.length < 6) return 'Mínimo 6 caracteres.';
    return null;
  }

  static String? notEmpty(String? value, {String field = 'Este campo'}) {
    if ((value?.trim() ?? '').isEmpty) return '$field es obligatorio.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Las contraseñas no coinciden.';
    return null;
  }
}
