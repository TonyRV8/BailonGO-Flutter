import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/error/exceptions.dart';

/// Selector de cuentas de Google. Separado del datasource para poder probar
/// el flujo de Firebase sin el plugin nativo.
abstract interface class GoogleIdTokenSource {
  /// Abre el selector y devuelve el ID token de la cuenta elegida, o `null`
  /// si el usuario lo cierra sin elegir.
  Future<String?> pickIdToken();

  /// Olvida la cuenta elegida, para que el próximo ingreso vuelva a preguntar.
  Future<void> signOut();
}

/// Implementación con `google_sign_in` (selector nativo de Android/iOS). En
/// Android el client ID web se toma de google-services.json (recurso
/// `default_web_client_id`), así que no hay IDs escritos en el código.
class GoogleSignInIdTokenSource implements GoogleIdTokenSource {
  Future<void>? _ready;

  Future<void> _init() => _ready ??= GoogleSignIn.instance.initialize();

  @override
  Future<String?> pickIdToken() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw AuthException(
            'El inicio con Google no está configurado en esta app.',
            code: 'google-missing-id-token');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthException(_message(e.code), code: 'google-${e.code.name}');
    }
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
  }

  String _message(GoogleSignInExceptionCode code) => switch (code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'El inicio con Google no está configurado en esta app.',
        GoogleSignInExceptionCode.interrupted ||
        GoogleSignInExceptionCode.uiUnavailable =>
          'No se pudo abrir el selector de cuentas de Google.',
        _ => 'No se pudo iniciar sesión con Google.',
      };
}
