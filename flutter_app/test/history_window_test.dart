// Free-tier history window.
//
// Free accounts chart and analyse the last kFreeHistoryDays; premium sees
// everything. The full history always stays in AppState.measurements — the
// window is applied at read time, so nothing is deleted and the parent can
// be told exactly how much is locked.
//
// The case that matters most is a parent who measures every couple of
// months. A naive cutoff shows them a blank chart, which reads as "the app
// lost my child's data" rather than "upgrade to see more".

import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/app_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _daysAgo(int n) => DateTime.now()
    .subtract(Duration(days: n))
    .toIso8601String()
    .split('T')
    .first;

/// Newest-first, matching what loadMeasurements() returns.
AppState _appWith({required bool premium, required List<int> agesInDays}) {
  final app = AppState(SupabaseClient('https://example.supabase.co', 'test'));
  app.account = {
    'subscription_tier': premium ? 'premium' : 'free',
    'tier_expires_at': null,
  };
  final sorted = [...agesInDays]..sort();
  app.measurements = [
    for (final d in sorted)
      {'measurement_id': d, 'recorded_date': _daysAgo(d), 'stature_height_cm': 120.0},
  ];
  return app;
}

void main() {
  group('visibleMeasurements', () {
    test('premium sees the full history', () {
      final app = _appWith(premium: true, agesInDays: [1, 40, 200, 900]);
      expect(app.visibleMeasurements.length, 4);
      expect(app.lockedMeasurementCount, 0);
      expect(app.hasLockedHistory, isFalse);
    });

    test('free sees only measurements inside the window', () {
      final app = _appWith(premium: false, agesInDays: [1, 10, 29, 40, 200]);
      expect(app.visibleMeasurements.length, 3); // 1, 10, 29
      expect(app.lockedMeasurementCount, 2); // 40, 200
      expect(app.hasLockedHistory, isTrue);
    });

    test('free with nothing inside the window still sees the latest point', () {
      // The blank-chart case: measured every ~2 months, nothing recent.
      final app = _appWith(premium: false, agesInDays: [45, 110, 260]);
      expect(app.visibleMeasurements.length, 1);
      expect(app.visibleMeasurements.single['recorded_date'], _daysAgo(45));
      expect(app.lockedMeasurementCount, 2);
    });

    test('no measurements at all yields an empty list, not a crash', () {
      final app = _appWith(premium: false, agesInDays: []);
      expect(app.visibleMeasurements, isEmpty);
      expect(app.lockedMeasurementCount, 0);
      expect(app.hasLockedHistory, isFalse);
    });

    test('a measurement exactly on the boundary is visible', () {
      final app = _appWith(premium: false, agesInDays: [AppState.kFreeHistoryDays]);
      expect(app.visibleMeasurements.length, 1);
      expect(app.lockedMeasurementCount, 0);
    });

    test('expired premium is windowed like free', () {
      final app = _appWith(premium: false, agesInDays: [1, 90]);
      app.account = {
        'subscription_tier': 'premium',
        'tier_expires_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      };
      expect(app.visibleMeasurements.length, 1);
      expect(app.lockedMeasurementCount, 1);
    });

    test('an unparseable date is kept rather than silently dropped', () {
      final app = _appWith(premium: false, agesInDays: [1]);
      app.measurements = [
        ...app.measurements,
        {'measurement_id': 99, 'recorded_date': 'not-a-date'},
      ];
      expect(app.visibleMeasurements.length, 2);
      expect(app.lockedMeasurementCount, 0);
    });
  });
}
