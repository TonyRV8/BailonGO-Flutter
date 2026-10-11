import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:webview_flutter/webview_flutter.dart';

/// Web: `<model-viewer>` es un platform view en el propio documento, así que
/// el script se evalúa directamente en la página (no hay WebView).
Future<void> runViewerScript(WebViewController? webView, String script) async {
  globalContext.callMethod('eval'.toJS, script.toJS);
}
