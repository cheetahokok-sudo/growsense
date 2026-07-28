// Free-tier lifetime measurement cap.
//
// This is the primary paywall: multi-year height velocity is the paid
// value, so free accounts get five lifetime measurements. The counter is
// user_accounts.total_measurements_logged, maintained by a database
// trigger and never decremented — deleting a measurement must not hand a
// slot back, or the cap is bypassed by delete-and-re-add.
//
// The subtle case is editing. addMeasurement upserts on
// (child_id, recorded_date), so re-saving an existing date is an UPDATE,
// not a new row. A capped parent must still be able to correct a height
// they typed wrong; blocking that would be indistinguishable from a bug.

import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/app_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AppState _app({
  required bool premium,
  required int logged,
  List<String> existingDates = const [],
}) {
  final app = AppState(SupabaseClient('https://example.supabase.co', 'test'));
  app.account = {
    'subscription_tier': premium ? 'premium' : 'free',
    'tier_expires_at': null,
    'total_measurements_logged': logged,
  };
  app.measurements = [
    for (final d in existingDates) {'recorded_date': d},
  ];
  return app;
}

void main() {
  group('canAddMeasurement', () {
    test('free under the cap can add', () {
      expect(_app(premium: false, logged: 4).canAddMeasurement, isTrue);
    });

    test('free at the cap cannot add', () {
      expect(_app(premium: false, logged: 5).canAddMeasurement, isFalse);
    });

    test('free over the cap cannot add', () {
      // Defensive: the trigger could outrun the client after a sync.
      expect(_app(premium: false, logged: 9).canAddMeasurement, isFalse);
    });

    test('premium is never capped', () {
      expect(_app(premium: true, logged: 900).canAddMeasurement, isTrue);
    });

    test('a missing counter is treated as zero, not as blocked', () {
      final app = _app(premium: false, logged: 0);
      app.account = {'subscription_tier': 'free'}; // column absent
      expect(app.measurementsLogged, 0);
      expect(app.canAddMeasurement, isTrue);
    });
  });

  group('measurementsRemaining', () {
    test('counts down and floors at zero', () {
      expect(_app(premium: false, logged: 0).measurementsRemaining, 5);
      expect(_app(premium: false, logged: 3).measurementsRemaining, 2);
      expect(_app(premium: false, logged: 5).measurementsRemaining, 0);
      expect(_app(premium: false, logged: 8).measurementsRemaining, 0);
    });

    test('null on premium, meaning unlimited rather than zero left', () {
      expect(_app(premium: true, logged: 3).measurementsRemaining, isNull);
    });
  });

  group('isNewMeasurementDate', () {
    test('a date already recorded is an edit, not a new measurement', () {
      final app = _app(
        premium: false,
        logged: 5,
        existingDates: ['2026-07-01', '2026-07-15'],
      );
      expect(app.isNewMeasurementDate('2026-07-15'), isFalse);
      expect(app.isNewMeasurementDate('2026-07-28'), isTrue);
    });

    test('a capped parent can still edit an existing measurement', () {
      // The regression this guards: at the cap, correcting a typo in a
      // height already entered must not be refused.
      final app = _app(
        premium: false,
        logged: 5,
        existingDates: ['2026-07-15'],
      );
      expect(app.canAddMeasurement, isFalse);
      expect(app.isNewMeasurementDate('2026-07-15'), isFalse);
      // addMeasurement gates on (isNewMeasurementDate && !canAddMeasurement),
      // so this combination is allowed through to the upsert.
    });

    test('no measurements loaded means every date is new', () {
      expect(
        _app(premium: false, logged: 0).isNewMeasurementDate('2026-07-28'),
        isTrue,
      );
    });
  });
}
