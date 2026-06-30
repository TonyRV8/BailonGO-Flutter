/// Entidad de dominio de un paso del catálogo (colección CATALOG, doc 5.3.3).
/// Independiente de Firebase: la capa data mapea desde/hacia esta entidad.
class DanceStep {
  const DanceStep({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.orden,
    this.mediaUrl,
    this.duracionCicloSeg = 0,
  });

  /// pasoId (identificador del documento en CATALOG).
  final String id;
  final String nombre;
  final String descripcion;

  /// Posición en el listado (RF-05).
  final int orden;

  /// URL del video ideal en bucle (RF-07). `null` hasta grabar las tomas.
  final String? mediaUrl;

  /// Duración de un ciclo del paso, en segundos (define la ventana de captura).
  final double duracionCicloSeg;

  bool get hasVideo => mediaUrl != null && mediaUrl!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DanceStep &&
      other.id == id &&
      other.nombre == nombre &&
      other.descripcion == descripcion &&
      other.orden == orden &&
      other.mediaUrl == mediaUrl &&
      other.duracionCicloSeg == duracionCicloSeg;

  @override
  int get hashCode =>
      Object.hash(id, nombre, descripcion, orden, mediaUrl, duracionCicloSeg);
}
