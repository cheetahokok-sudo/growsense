// ══════════════════════════════════════════════════════════════════
// i18n — Flutter counterpart of the PWA's t(key) helper.
// Locale JSON lives in assets/locales/, generated from the PWA's
// locales/ folder (the source of truth) plus flutter_extra_keys.json
// by tool/sync_locales.js. Same flat dot-keys as the PWA, so both
// clients share one translation set.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

const supportedLanguages = {
  'en': 'English',
  'th': 'ภาษาไทย',
  'vi': 'Tiếng Việt',
  'ko': '한국어',
  'zh': '中文',
  'ar': 'العربية',
};

const _prefsKey = 'gs_locale';

class I18n extends ChangeNotifier {
  String code = 'en';
  Map<String, String> _strings = {};
  Map<String, String> _fallback = {};

  bool get isRtl => code == 'ar';
  Locale get locale => Locale(code);

  static Future<I18n> create() async {
    final i18n = I18n();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    i18n._fallback = await _loadLang('en');
    if (saved != null && supportedLanguages.containsKey(saved)) {
      i18n.code = saved;
      i18n._strings =
          saved == 'en' ? i18n._fallback : await _loadLang(saved);
    } else {
      i18n._strings = i18n._fallback;
    }
    return i18n;
  }

  static Future<Map<String, String>> _loadLang(String lang) async {
    final raw = await rootBundle.loadString('assets/locales/$lang.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return j.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> setLanguage(String lang) async {
    if (!supportedLanguages.containsKey(lang) || lang == code) return;
    code = lang;
    _strings = lang == 'en' ? _fallback : await _loadLang(lang);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang);
  }

  /// Translate a key; falls back to English, then to [fallback], then
  /// to the key itself. `{n}`-style placeholders are replaced from
  /// [params].
  String t(String key, [String? fallback, Map<String, String>? params]) {
    var s = _strings[key] ?? _fallback[key] ?? fallback ?? key;
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }
}
