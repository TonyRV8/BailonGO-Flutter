import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/dance_step.dart';

/// Mapeo entre la entidad [DanceStep] y el documento Firestore de CATALOG.
class DanceStepModel extends DanceStep {
  const DanceStepModel({
    required super.id,
    required super.nombre,
    required super.descripcion,
    required super.orden,
    super.mediaUrl,
    super.duracionCicloSeg,
  });

  factory DanceStepModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return DanceStepModel(
      id: doc.id,
      nombre: (data['nombre'] as String?) ?? '',
      descripcion: (data['descripcion'] as String?) ?? '',
      orden: (data['orden'] as num?)?.toInt() ?? 0,
      mediaUrl: data['mediaUrl'] as String?,
      duracionCicloSeg: (data['duracionCicloSeg'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Documento listo para `set()` al sembrar el catálogo.
  Map<String, dynamic> toFirestore() => {
        'nombre': nombre,
        'descripcion': descripcion,
        'orden': orden,
        'mediaUrl': mediaUrl,
        'duracionCicloSeg': duracionCicloSeg,
      };
}
