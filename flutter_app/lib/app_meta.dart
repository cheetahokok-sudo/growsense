// ══════════════════════════════════════════════════════════════════
// App metadata — single source of truth for the version shown in
// Account, the "What's new" screen, and every bug report.
//
// RELEASE PROCESS (keep these three in lockstep with CHANGELOG.md and
// assets/release_notes.json):
//   1. Bump kAppVersion (semver: MAJOR.MINOR.PATCH).
//        PATCH  = bug fixes only
//        MINOR  = new user-facing feature, backwards compatible
//        MAJOR  = breaking change to data or flows
//   2. Increment kAppBuild by 1 on every deploy (never reused).
//   3. Set kBuildDate to the release date (YYYY-MM-DD).
//   4. Add the matching entry to CHANGELOG.md and release_notes.json.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show kIsWeb;

const String kAppVersion = '1.0.0';
const int kAppBuild = 1;
const String kBuildDate = '2026-07-11';

/// Where this build runs — used for triaging platform-specific bugs.
String get kAppChannel => kIsWeb ? 'web' : 'app';

/// Human-readable version stamp for the Account row, e.g.
/// "1.0.0 (build 1) · 2026-07-11".
String get versionStamp => '$kAppVersion (build $kAppBuild) · $kBuildDate';

/// The short version + build used inside bug reports and filenames.
String get versionShort => '$kAppVersion+$kAppBuild';
