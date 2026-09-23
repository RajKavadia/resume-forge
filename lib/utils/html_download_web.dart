import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [html] as [fileName].
Future<String> downloadHtmlFile({
  required String html,
  required String fileName,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(html));
  final blobParts = [bytes.toJS].toJS;
  final blob = web.Blob(
    blobParts,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return 'download:$fileName';
}
