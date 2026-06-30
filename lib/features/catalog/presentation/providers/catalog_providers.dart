import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasources/catalog_remote_data_source.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/dance_step.dart';
import '../../domain/repositories/catalog_repository.dart';

// --- Capa data ---------------------------------------------------------------

final catalogRemoteDataSourceProvider = Provider<CatalogRemoteDataSource>(
  (ref) => CatalogRemoteDataSource(
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(ref.watch(catalogRemoteDataSourceProvider)),
);

// --- Datos para la UI --------------------------------------------------------

/// Listado completo de pasos (RF-05).
final catalogProvider = FutureProvider<List<DanceStep>>((ref) {
  return ref.watch(catalogRepositoryProvider).getCatalog();
});

/// Un paso por id (para la ficha, RF-06). Lo resuelve desde el listado ya
/// cargado para no volver a pegarle a la red.
final stepByIdProvider = Provider.family<DanceStep?, String>((ref, id) {
  final steps = ref.watch(catalogProvider).value;
  if (steps == null) return null;
  for (final s in steps) {
    if (s.id == id) return s;
  }
  return null;
});

/// Mejor precisión histórica del usuario en un paso (RF-06). `null` sin marca.
final bestScoreProvider =
    FutureProvider.family<double?, String>((ref, pasoId) async {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return null;
  return ref
      .watch(catalogRepositoryProvider)
      .bestScoreFor(uid: user.uid, pasoId: pasoId);
});
