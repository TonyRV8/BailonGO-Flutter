import 'dart:io';

import 'package:flutter/services.dart';

import '../../pose/domain/entities/pose_landmark.dart';
import '../engine/feature_extractor.dart';

/// Procesa un video (asset o archivo) con MediaPipe en modo VIDEO vía el
/// platform channel y devuelve la secuencia de vectores de features (una por
/// fotograma con cuerpo válido). Porta la idea de `VideoProcessor.kt`.
class VideoPoseProcessor {
  static const MethodChannel _channel = MethodChannel('bailongo/pose');

  /// Extrae features de un asset empaquetado (p.ej. `assets/videos/ref.mov`).
  Future<List<List<double>>> processAsset(String assetPath) async {
    final file = await _assetToTempFile(assetPath);
    return processFile(file.path);
  }

  /// Extrae features de un archivo en disco.
  Future<List<List<double>>> processFile(String path) async {
    final res = await _channel.invokeMethod<Object?>('processVideo', {'path': path});
    // El nativo devuelve {aspect, frames}; versiones anteriores, solo frames.
    final List<dynamic>? raw;
    var aspect = 1.0;
    if (res is Map) {
      raw = res['frames'] as List<dynamic>?;
      final a = (res['aspect'] as num?)?.toDouble() ?? 0;
      if (a > 0) aspect = a;
    } else {
      raw = res as List<dynamic>?;
    }
    if (raw == null) return const [];

    final feats = <List<double>>[];
    for (final fr in raw) {
      final flat = (fr as List).map((e) => (e as num).toDouble()).toList();
      final landmarks = <PoseLandmark>[];
      for (var i = 0; i + 3 < flat.length; i += 4) {
        landmarks.add(PoseLandmark(
          type: i ~/ 4,
          x: flat[i],
          y: flat[i + 1],
          z: flat[i + 2],
          confidence: flat[i + 3],
        ));
      }
      final v = FeatureExtractor.extractFeatures(landmarks, aspectRatio: aspect);
      if (v != null) feats.add(v);
    }
    return feats;
  }

  Future<File> _assetToTempFile(String asset) async {
    final data = await rootBundle.load(asset);
    final file = File('${Directory.systemTemp.path}/${asset.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file;
  }
}
