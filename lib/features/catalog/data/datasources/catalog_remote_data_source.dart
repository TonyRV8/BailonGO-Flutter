import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/step_stats.dart';
import '../catalog_seed.dart';
import '../models/dance_step_model.dart';

/// Fuente de datos remota del catálogo (colección CATALOG en Firestore).
class CatalogRemoteDataSource {
  CatalogRemoteDataSource({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _firestore.collection(AppConstants.catalogCollection);

  CollectionReference<Map<String, dynamic>> get _history =>
      _firestore.collection(AppConstants.historyCollection);

  /// Listado completo de pasos ordenado (RF-05). Lanza si falla la red y no
  /// hay cache; el repo decide el fallback al seed local.
  Future<List<DanceStepModel>> fetchCatalog() async {
    try {
      final snap = await _catalog.orderBy('orden').get();
      return snap.docs.map(DanceStepModel.fromFirestore).toList();
    } catch (e) {
      throw ServerException('No se pudo leer el catálogo: $e');
    }
  }

  /// Mejor precisión histórica del usuario en un paso (RF-06 / RN-04).
  /// Devuelve `null` si aún no hay intentos.
  Future<double?> bestScoreFor({
    required String uid,
    required String pasoId,
  }) async {
    final all = await statsForUser(uid);
    return all[pasoId]?.best;
  }

  /// Mejor precisión por paso para un usuario (mapa pasoId → total).
  Future<Map<String, double>> bestScoresForUser(String uid) async {
    final stats = await statsForUser(uid);
    return {
      for (final e in stats.entries)
        if (e.value.best != null) e.key: e.value.best!,
    };
  }

  /// Mejor precisión y número de intentos por paso, en UNA sola lectura de
  /// HISTORY filtrando por `uid` (campo único, auto-indexado: no hace falta
  /// índice compuesto). El máximo y el conteo se calculan en cliente.
  Future<Map<String, StepStats>> statsForUser(String uid) async {
    try {
      final snap = await _history.where('uid', isEqualTo: uid).get();
      final best = <String, double>{};
      final count = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final pasoId = data['pasoId'] as String?;
        if (pasoId == null) continue;
        count[pasoId] = (count[pasoId] ?? 0) + 1;
        final total =
            ((data['scores'] as Map<String, dynamic>?)?['total'] as num?)
                ?.toDouble();
        if (total == null) continue;
        final current = best[pasoId];
        if (current == null || total > current) best[pasoId] = total;
      }
      return {
        for (final pasoId in count.keys)
          pasoId: StepStats(best: best[pasoId], attempts: count[pasoId]!),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Siembra los 9 pasos del seed en CATALOG (seeder dev, plan.txt §FASE 2).
  /// Requiere relajar temporalmente la regla de escritura de `catalog`.
  Future<void> seedCatalog() async {
    try {
      final batch = _firestore.batch();
      for (final step in kCatalogSeed) {
        batch.set(_catalog.doc(step.id), step.toFirestore());
      }
      await batch.commit();
    } catch (e) {
      throw ServerException('No se pudo sembrar el catálogo: $e');
    }
  }
}
