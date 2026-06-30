import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('bailongo/pose');

/// Extrae un frame (JPEG) del centro de un video asset, para usarlo de portada
/// en el catálogo. `null` si falla.
Future<Uint8List?> videoThumbnailAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    final file =
        File('${Directory.systemTemp.path}/thumb_${assetPath.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return _channel.invokeMethod<Uint8List>('videoThumbnail', {'path': file.path});
  } catch (_) {
    return null;
  }
}
