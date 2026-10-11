import 'package:webview_flutter/webview_flutter.dart';

/// Android / iOS: `<model-viewer>` vive dentro del WebView del visor.
Future<void> runViewerScript(WebViewController? webView, String script) async {
  await webView?.runJavaScript(script);
}
