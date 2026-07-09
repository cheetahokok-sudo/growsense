/// Non-web fallback — the native builds will wire share_plus /
/// path_provider here when the iOS app lands.
Future<String?> downloadTextFile(String filename, String content) async =>
    'Download is only available in the web app for now';
