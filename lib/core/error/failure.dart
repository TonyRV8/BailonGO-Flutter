/// Representa un fallo de dominio (capa presentación lo muestra al usuario).
sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Fallo de autenticación (credenciales, sesión, etc.).
class AuthFailure extends Failure {
  const AuthFailure(super.message, {this.code});
  final String? code;
}

/// Fallo de red / conectividad.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Sin conexión a la red.']);
}

/// Fallo de servidor / backend (Firestore, Functions).
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Error del servidor.']);
}

/// Fallo no clasificado.
class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Ocurrió un error inesperado.']);
}
