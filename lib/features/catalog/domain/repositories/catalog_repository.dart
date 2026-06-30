import '../entities/dance_step.dart';

/// Contrato del catálogo (capa de dominio). La capa data lo implementa con
/// Firestore + fallback al seed local.
abstract class CatalogRepository {
  /// Listado completo de pasos ordenado (RF-05).
  Future<List<DanceStep>> getCatalog();

  /// Mejor precisión histórica del usuario en un paso (RF-06). `null` sin marca.
  Future<double?> bestScoreFor({required String uid, required String pasoId});

  /// Mejor precisión por paso del usuario (mapa pasoId → total, 0..100).
  Future<Map<String, double>> bestScoresForUser(String uid);

  /// Siembra el catálogo en Firestore (uso dev).
  Future<void> seedCatalog();
}
