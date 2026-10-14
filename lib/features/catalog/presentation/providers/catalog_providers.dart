import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/datasources/catalog_remote_data_source.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../data/video_thumbnail.dart';
import '../../domain/entities/dance_step.dart';
import '../../domain/entities/step_stats.dart';
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

/// Métricas del usuario por paso (mejor precisión + intentos). Es la ÚNICA
/// lectura de HISTORY: el resto de providers de progreso se derivan de aquí,
/// así que invalidando este se refrescan todos.
final userStepStatsProvider =
    FutureProvider<Map<String, StepStats>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const {};
  return ref.watch(catalogRepositoryProvider).statsForUser(user.uid);
});

/// Métricas de un paso concreto (ficha del paso, RF-06).
final stepStatsProvider =
    FutureProvider.family<StepStats, String>((ref, pasoId) async {
  final stats = await ref.watch(userStepStatsProvider.future);
  return stats[pasoId] ?? StepStats.empty;
});

/// Mejor precisión histórica del usuario en un paso (RF-06). `null` sin marca.
final bestScoreProvider =
    FutureProvider.family<double?, String>((ref, pasoId) async {
  return (await ref.watch(stepStatsProvider(pasoId).future)).best;
});

/// Mejor precisión por paso del usuario (mapa pasoId → total). Para el progreso
/// (RF-03).
final userBestScoresProvider = FutureProvider<Map<String, double>>((ref) async {
  final stats = await ref.watch(userStepStatsProvider.future);
  return {
    for (final e in stats.entries)
      if (e.value.best != null) e.key: e.value.best!,
  };
});

/// Portada del paso: un frame del video de referencia (clave = mediaUrl).
/// `null` si el paso no tiene video.
final stepThumbnailProvider =
    FutureProvider.family<Uint8List?, String>((ref, mediaUrl) async {
  if (!mediaUrl.startsWith('assets/')) return null;
  return videoThumbnailAsset(mediaUrl);
});
