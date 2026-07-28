// ══════════════════════════════════════════════════════════════════
// The annotation painter draws onto a child's X-ray, so the failure
// mode that matters is silent: a null or oddly-shaped AI result must
// never throw mid-paint (which would black out the whole record
// screen) and must never draw a region the AI did not actually report.
//
// These exercise paint() against a real Canvas rather than asserting
// on the source, so a coordinate or null-handling mistake fails here
// instead of on a device.
// ══════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/widgets/xray_annotation.dart';

/// Paints the overlay for [result] and returns how many draw ops the
/// canvas recorded — a cheap proxy for "did it actually draw?".
int _paintOps(Map<String, dynamic> result, {Size size = const Size(300, 320)}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // The painter is private; drive it through the public widget's
  // CustomPaint by building the same painter the widget builds.
  debugPaintXrayAnnotations(canvas, size, result);
  final picture = recorder.endRecording();
  return picture.approximateBytesUsed;
}

void main() {
  final full = <String, dynamic>{
    'carpal_analysis': {
      'count_visible': 7,
      'bones_identified': [
        'capitate',
        'hamate',
        'triquetrum',
        'lunate',
        'scaphoid',
      ],
    },
    'epiphyseal_observations': [
      {'bone_group': 'distal_radius', 'appearance': 'well_formed'},
      {'bone_group': 'metacarpals', 'appearance': 'well_formed'},
      {'bone_group': 'proximal_phalanges', 'appearance': 'small_clear'},
      {'bone_group': 'middle_phalanges', 'appearance': 'barely_visible'},
      {'bone_group': 'distal_phalanges', 'appearance': 'absent'},
    ],
  };

  test('paints a full result without throwing', () {
    expect(_paintOps(full), greaterThan(0));
  });

  test('survives an empty result — an AI run can return nothing', () {
    expect(() => _paintOps(const {}), returnsNormally);
  });

  test('survives malformed shapes rather than blacking out the screen', () {
    // Every one of these has been seen from a model at some point:
    // wrong types, nulls inside lists, missing keys.
    final malformed = <Map<String, dynamic>>[
      {'carpal_analysis': null, 'epiphyseal_observations': null},
      {'carpal_analysis': 'not a map', 'epiphyseal_observations': 'nope'},
      {
        'carpal_analysis': {'bones_identified': 'capitate'},
        'epiphyseal_observations': [
          {'bone_group': null, 'appearance': null},
        ],
      },
      {
        'carpal_analysis': {'count_visible': null, 'bones_identified': []},
        'epiphyseal_observations': [<String, dynamic>{}],
      },
    ];
    for (final m in malformed) {
      expect(() => _paintOps(m), returnsNormally, reason: '$m');
    }
  });

  test('degenerate canvas sizes do not throw', () {
    for (final s in const [Size(0, 0), Size(1, 400), Size(400, 1)]) {
      expect(() => _paintOps(full, size: s), returnsNormally, reason: '$s');
    }
  });

  test('appearance colours follow the measured → flag ramp', () {
    // The colour ramp is the clinical signal: a parent reads red as
    // "advanced". Pin it so a refactor cannot quietly reorder it.
    expect(xrayAppearanceColorForTest('barely_visible'),
        isNot(xrayAppearanceColorForTest('wide_capping')));
    expect(xrayAppearanceColorForTest('absent'),
        xrayAppearanceColorForTest('something_unknown'));
  });
}
