import '../../catalog/domain/entities/dance_step.dart';
import 'reference_asset_source.dart';
import 'reference_remote_data_source.dart';
import 'video_pose_processor.dart';

/// Obtiene los frames de features de referencia de un paso. Orden de búsqueda:
///   1. Cache en memoria (sesión actual).
///   2. Asset empaquetado `assets/references/<pasoId>.json` (landmarks; las
///      features se calculan con el extractor vigente).
///   3. Firestore REFERENCE_DATA, solo si se generó con la versión actual del
///      extractor (las anteriores no corrigen el aspecto ni traen la cadera).
///   4. Extracción del video asset (fallback; lento, solo si nunca se subió).
class ReferenceRepository {
  ReferenceRepository(this._processor, this._remote, [ReferenceAssetSource? assets])
      : _assets = assets ?? ReferenceAssetSource();

  final VideoPoseProcessor _processor;
  final ReferenceRemoteDataSource _remote;
  final ReferenceAssetSource _assets;
  final Map<String, List<List<double>>> _cache = {};

  Future<List<List<double>>> framesFor(DanceStep step) async {
    final cached = _cache[step.id];
    if (cached != null) return cached;

    final fromAsset = await _assets.load(step.id);
    if (fromAsset != null && fromAsset.isNotEmpty) {
      _cache[step.id] = fromAsset;
      return fromAsset;
    }

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
  /// sola vez aunque lo compartan (copias del paso de prueba). La caché de
  /// sesión se llena aunque falle la subida (p.ej. reglas cerradas), para no
  /// perder la extracción; el error se relanza al final.
  ///
  /// Devuelve el nº de fotogramas válidos por `pasoId`, para poder verificar
  /// que se acerca a `duracion_ms / 33` (implementar_pasos.txt §3).
  Future<Map<String, int>> extractAndUploadAll(List<DanceStep> steps) async {
    final byUrl = <String, List<List<double>>>{};
    final frames = <String, int>{};
    Object? firstError;
    for (final step in steps) {
      if (!step.hasVideo) continue;
      final f = byUrl[step.mediaUrl!] ??=
          await _processor.processAsset(step.mediaUrl!);
      _cache[step.id] = f;
      frames[step.id] = f.length;
      try {
        await _remote.save(step.id, f);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
    return frames;
  }
}
