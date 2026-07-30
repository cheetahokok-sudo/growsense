// ══════════════════════════════════════════════════════════════════
// Flutter and the PWA write the same Supabase tables, and those tables
// carry CHECK constraints built around the PWA's vocabulary. When the
// two drift, the *only* symptom is a save that fails on device with a
// constraint-violation message no parent can act on — it does not show
// up in `flutter analyze`, in a widget test, or anywhere on web.
//
// This has now happened twice: illness_events, and
// bone_age_assessments.method (Flutter sent 'greulich_pyle' where the
// constraint expects 'GP'). This test pins the vocabulary to the PWA's
// <select> options, which are the same strings app.js inserts.
// ══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Values of the `<option>` tags inside the named `<select>` in webapp.html.
Set<String> _pwaSelectValues(String html, String selectId) {
  final open = html.indexOf('id="$selectId"');
  expect(open, isNot(-1), reason: 'no <select id="$selectId"> in webapp.html');
  final close = html.indexOf('</select>', open);
  final block = html.substring(open, close);
  return RegExp('value="([^"]*)"')
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('bone age method values match the web app (DB CHECK constraint)', () {
    final html = File('../webapp.html').readAsStringSync();
    final dart = File('lib/screens/bone_age_screen.dart').readAsStringSync();

    final allowed = _pwaSelectValues(html, 'boneAgeMethod');
    expect(allowed, contains('GP'));

    // Every DropdownMenuItem value in the method dropdown, plus the
    // field's initial value.
    final dropdown = dart.substring(
        dart.indexOf('DropdownButtonFormField<String>('),
        dart.indexOf('onChanged: (v) => setState(() => _method = v!)'));
    final sent = RegExp("value: '([^']*)'")
        .allMatches(dropdown)
        .map((m) => m.group(1)!)
        .toSet()
      ..add(RegExp("String _method = '([^']*)'").firstMatch(dart)!.group(1)!);

    expect(sent, isNotEmpty);
    expect(sent.difference(allowed), isEmpty,
        reason: 'Flutter would insert bone_age_assessments.method values the '
            'CHECK constraint rejects. Allowed (from webapp.html): $allowed');
  });
}
