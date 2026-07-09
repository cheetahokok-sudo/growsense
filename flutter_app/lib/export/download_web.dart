import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser download: Blob → object URL → synthetic anchor click.
/// Returns null on success, an error string on failure.
Future<String?> downloadTextFile(String filename, String content) async {
  try {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return null;
  } catch (e) {
    return e.toString();
  }
}
