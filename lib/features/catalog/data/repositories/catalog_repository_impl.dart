import '../../domain/entities/dance_step.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../catalog_seed.dart';
import '../datasources/catalog_remote_data_source.dart';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._remote);

  final CatalogRemoteDataSource _remote;

  @override
  Future<List<DanceStep>> getCatalog() async {
    try {
      final steps = await _remote.fetchCatalog();
      // Si Firestore aún no está sembrado, usar el seed local (offline-first).
      if (steps.isEmpty) return List<DanceStep>.from(kCatalogSeed);
      return steps;
    } catch (_) {
      // Sin red ni cache: degradar al seed local empaquetado.
      return List<DanceStep>.from(kCatalogSeed);
    }
  }

  @override
  Future<double?> bestScoreFor({
    required String uid,
    required String pasoId,
  }) =>
      _remote.bestScoreFor(uid: uid, pasoId: pasoId);

  @override
  Future<void> seedCatalog() => _remote.seedCatalog();
}
