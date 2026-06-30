/// Excepciones de la capa de datos (datasources). La capa repos las traduce
/// a [Failure] del dominio.
class AuthException implements Exception {
  AuthException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'AuthException($code): $message';
}

class ServerException implements Exception {
  ServerException([this.message = 'Error del servidor.']);
  final String message;

  @override
  String toString() => 'ServerException: $message';
}

class CacheException implements Exception {
  CacheException([this.message = 'Error de cache local.']);
  final String message;

  @override
  String toString() => 'CacheException: $message';
}
