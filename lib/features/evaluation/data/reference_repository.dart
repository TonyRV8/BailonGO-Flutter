import '../../catalog/domain/entities/dance_step.dart';
import 'reference_remote_data_source.dart';
import 'video_pose_processor.dart';

/// Obtiene los frames de features de referencia de un paso. Orden de búsqueda:
///   1. Cache en memoria (sesión actual).
///   2. Firestore REFERENCE_DATA (extraído una sola vez → carga instantánea).
///   3. Extracción del video asset (fallback; lento, solo si nunca se subió).
class ReferenceRepository {
  ReferenceRepository(this._processor, this._remote);

  final VideoPoseProcessor _processor;
  final ReferenceRemoteDataSource _remote;
  final Map<String, List<List<double>>> _cache = {};

  Future<List<List<double>>> framesFor(DanceStep step) async {
    final cached = _cache[step.id];
    if (cached != null) return cached;

    final fromDb = await _remote.load(step.id);
    if (fromDb != null && fromDb.isNotEmpty) {
      _cache[step.id] = fromDb;
      return fromDb;
    }

    if (!step.hasVideo) return const [];
    final url = step.mediaUrl!;
    final frames =
        url.startsWith('assets/') ? await _processor.processAsset(url) : <List<double>>[];
    _cache[step.id] = frames;
    return frames;
  }

  /// Dev: extrae la referencia del video y la sube a Firestore para cargas
  /// instantáneas posteriores.
  Future<int> extractAndUpload(DanceStep step) async {
    if (!step.hasVideo) return 0;
    final frames = await _processor.processAsset(step.mediaUrl!);
    await _remote.save(step.id, frames);
    _cache[step.id] = frames;
    return frames.length;
  }

  /// Dev: como [extractAndUpload] para varios pasos, extrayendo cada video una
  /// sola vez aunque lo compartan (copias del paso de prueba).
  Future<int> extractAndUploadAll(List<DanceStep> steps) async {
    final byUrl = <String, List<List<double>>>{};
    var frames = 0;
    for (final step in steps) {
      if (!step.hasVideo) continue;
      final f = byUrl[step.mediaUrl!] ??=
          await _processor.processAsset(step.mediaUrl!);
      await _remote.save(step.id, f);
      _cache[step.id] = f;
      frames = f.length;
    }
    return frames;
  }
}
