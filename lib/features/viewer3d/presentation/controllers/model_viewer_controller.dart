import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'viewer_script_runner_io.dart'
    if (dart.library.js_interop) 'viewer_script_runner_web.dart';

/// Ángulos de cámara preestablecidos del visor 3D.
///
/// El maniquí mira hacia +Z (convención glTF), así que `theta = 0` es el
/// frente y su lado derecho queda en -X (`theta = -90°`).
enum CameraPreset {
  front('Frente', '0deg 75deg 4m', _body),
  right('Derecha', '-90deg 75deg 4m', _body),
  left('Izquierda', '90deg 75deg 4m', _body),
  back('Detrás', '180deg 75deg 4m', _body),
  feet('Pies', '20deg 60deg 2m', '0m -0.05m 0m');

  const CameraPreset(this.label, this.orbit, this.target);

  final String label;

  /// `camera-orbit` de `<model-viewer>`: "theta phi radio".
  final String orbit;

  /// `camera-target`: punto al que mira la cámara.
  final String target;
}

/// Objetivo de las vistas de cuerpo entero. Queda por debajo del centro del
/// maniquí (≈0.85 m) para subirlo en pantalla y que el panel inferior no le
/// tape los pies.
const _body = '0m 0.45m 0m';

/// Envía órdenes a `<model-viewer>` (animación, velocidad, cámara) y libera el
/// renderizado al salir.
///
/// En móvil necesita el [WebViewController] que expone `model_viewer_plus`
/// ([attach]); en web el elemento está en el documento y no hace falta. Tras
/// [release] todas las órdenes se ignoran.
class ModelViewerController {
  ModelViewerController({required this.minRadius, required this.maxRadius});

  /// Límites de zoom (radio de la órbita, en metros).
  final double minRadius;
  final double maxRadius;

  WebViewController? _webView;

  /// Liberación en curso o terminada (pop y dispose pueden pedirla a la vez).
  Future<void>? _release;

  bool get isReleased => _release != null;

  void attach(WebViewController webView) {
    if (!isReleased) _webView = webView;
  }

  /// Reproduce [animation] en bucle desde el inicio.
  Future<void> playAnimation(String animation) => _run(
        "mv.animationName = '${_escape(animation)}';"
        'mv.currentTime = 0;'
        'mv.play();',
      );

  /// Velocidad de reproducción (1 = normal).
  Future<void> setSpeed(double speed) => _run('mv.timeScale = $speed;');

  Future<void> setCamera(CameraPreset preset) => _run(
        "mv.cameraTarget = '${preset.target}';"
        "mv.cameraOrbit = '${preset.orbit}';"
        "mv.fieldOfView = 'auto';",
      );

  /// Acerca (`factor < 1`) o aleja (`factor > 1`) la cámara desde donde esté.
  Future<void> zoom(double factor) => _run(
        'var o = mv.getCameraOrbit();'
        'var r = Math.min(Math.max(o.radius * $factor, $minRadius), $maxRadius);'
        "mv.cameraOrbit = o.theta + 'rad ' + o.phi + 'rad ' + r + 'm';",
      );

  /// La app pasa a segundo plano: se detiene el bucle (y con él el render).
  Future<void> pause() => _run('mv.pause();');

  Future<void> resume() => _run('mv.play();');

  /// Detiene la animación, descarga el modelo (geometría, texturas y buffers
  /// de GPU de three.js) y, en móvil, vacía el WebView para que suelte el
  /// contexto WebGL sin esperar al recolector de basura. Idempotente.
  Future<void> release() => _release ??= _doRelease();

  Future<void> _doRelease() async {
    final webView = _webView;
    _webView = null;
    try {
      await runViewerScript(
        webView,
        _wrap("mv.pause(); mv.removeAttribute('src');"),
      );
      await webView?.loadHtmlString('<html><body></body></html>');
    } catch (e) {
      // El WebView puede estar ya destruido; no hay nada más que liberar.
      debugPrint('ModelViewerController.release: $e');
    }
  }

  Future<void> _run(String body) async {
    if (isReleased) return;
    try {
      await runViewerScript(_webView, _wrap(body));
    } catch (e) {
      // Orden enviada antes de que la página termine de cargar, o con el
      // WebView ya cerrándose: se descarta sin romper la UI.
      debugPrint('ModelViewerController: $e');
    }
  }

  /// Localiza `<model-viewer>` (también dentro de shadow roots, como en los
  /// platform views de Flutter web) y ejecuta [body] con él como `mv`.
  static String _wrap(String body) => '(function(){'
      'function find(root){'
      "var m = root.querySelector('model-viewer'); if (m) return m;"
      "var all = root.querySelectorAll('*');"
      'for (var i = 0; i < all.length; i++) {'
      'if (all[i].shadowRoot) { m = find(all[i].shadowRoot); if (m) return m; }'
      '}'
      'return null;'
      '}'
      'var mv = find(document); if (!mv) return;'
      '$body'
      '})();';

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
