import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/config/app_constants.dart';
import '../../../../core/error/exceptions.dart';
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
    try {
      final snap = await _history
          .where('uid', isEqualTo: uid)
          .where('pasoId', isEqualTo: pasoId)
          .orderBy('scores.total', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final scores = snap.docs.first.data()['scores'] as Map<String, dynamic>?;
      return (scores?['total'] as num?)?.toDouble();
    } catch (_) {
      // Sin red o índice ausente: degradar a "sin marca" (offline-first).
      return null;
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
