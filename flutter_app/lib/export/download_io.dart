// ══════════════════════════════════════════════════════════════════
// Native (iOS / Android / desktop) file export.
//
// The web build hands bytes to a Blob + synthetic anchor click. A
// device has no equivalent, so we write the file into the app's
// temporary directory and pass it to the system share sheet — the
// parent then picks Files, Mail, AirDrop, or a printer.
//
// Contract matches download_web.dart exactly: return null on success,
// an error string on failure. A share sheet the user *dismisses* is
// NOT a failure — they saw it and changed their mind.
//
// This file is what makes the visit-summary PDF and CSV export real on
// iOS. Before it existed the non-web branch returned the literal
// string "Download is only available in the web app for now", which
// behind a paywall would be both a broken paid feature (Guideline 2.1)
// and steering to the web (Guideline 3.1.1).
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// CSV / plain-text export.
Future<String?> downloadTextFile(String filename, String content) => _share(
      filename,
      Uint8List.fromList(utf8.encode(content)),
      'text/csv;charset=utf-8',
    );

/// Binary export (the generated visit-summary PDF).
Future<String?> downloadBytesFile(
        String filename, Uint8List bytes, String mime) =>
    _share(filename, bytes, mime);

Future<String?> _share(String filename, Uint8List bytes, String mime) async {
  try {
    final name = _safeName(filename);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime, name: name)],
        // Required on iPad/macOS: UIActivityViewController is presented
        // as a popover there and throws without a source rect. Apple
        // reviewed this app on an iPad, so a null origin here is a
        // crash in review, not a cosmetic issue.
        sharePositionOrigin: _popoverAnchor(),
      ),
    );

    if (result.status == ShareResultStatus.unavailable) {
      return 'Sharing is not available on this device';
    }
    // success or dismissed — both mean we did our job.
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Strip anything that can't be a filename on the target filesystem, so
/// a child's name in the PDF filename can't produce an invalid path.
String _safeName(String raw) {
  final cleaned =
      raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'growsense-export' : cleaned;
}

/// A small rect at the centre of the screen. iPad anchors the share
/// popover to this; every other platform ignores it.
ui.Rect? _popoverAnchor() {
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isEmpty) return null;
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  if (size.isEmpty) return null;
  return ui.Rect.fromCenter(
    center: ui.Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}
