// ══════════════════════════════════════════════════════════════════
// Insight Windows model layer — the pure functions behind the range
// chips. These are the paywall's load-bearing math: window slicing,
// vs-prior-period deltas, the sparse-record chip rule, and the
// clinical floor on windowed height velocity. All testable without a
// device or Supabase.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/analytics.dart';

List<DayMetrics> _days(int n, double? Function(int i) value,
    {bool Function(int i)? estimated}) {
  final base = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < n; i++)
      DayMetrics(base.add(Duration(days: i)).toIso8601String().substring(0, 10))
        ..proteinG = value(i)
        ..nutritionEstimated = estimated?.call(i) ?? false,
  ];
}

void main() {
  group('computeWindowStats', () {
    test('slices the trailing window and averages logged days only', () {
      // 60 days: first 30 at 10 g, last 30 at 20 g, every 3rd day null.
      final days = _days(60, (i) => i % 3 == 2 ? null : (i < 30 ? 10 : 20));
      final s = computeWindowStats(days, 30, (d) => d.proteinG);
      expect(s.days.length, 30);
      expect(s.avg, 20);
      expect(s.loggedCount, 20);
      // Prior 30 days averaged 10 → delta +10.
      expect(s.deltaVsPrior, 10);
    });

    test('delta is null when the prior window has no logs', () {
      final days = _days(40, (i) => i < 10 ? null : 15.0);
      // Window 30 → prior window is only the first 10 days, all null.
      final s = computeWindowStats(days, 30, (d) => d.proteinG);
      expect(s.avg, 15);
      expect(s.deltaVsPrior, isNull);
    });

    test('window wider than the record uses what exists', () {
      final days = _days(10, (i) => 5.0);
      final s = computeWindowStats(days, 90, (d) => d.proteinG);
      expect(s.days.length, 10);
      expect(s.avg, 5);
      expect(s.deltaVsPrior, isNull);
    });

    test('estimated days are counted for the honesty disclosure', () {
      final days =
          _days(30, (i) => 10.0, estimated: (i) => i >= 20); // last 10 est.
      final s = computeWindowStats(days, 30, (d) => d.proteinG,
          estimatedOf: (d) => d.nutritionEstimated);
      expect(s.estimatedCount, 10);
    });

    test('empty window returns nulls, not NaN', () {
      final days = _days(30, (i) => null);
      final s = computeWindowStats(days, 30, (d) => d.proteinG);
      expect(s.avg, isNull);
      expect(s.deltaVsPrior, isNull);
      expect(s.loggedCount, 0);
    });
  });

  group('windowHasEnoughRecord — the sparse-record chip rule', () {
    test('7d and 30d always render (free windows)', () {
      expect(windowHasEnoughRecord(7, 0), isTrue);
      expect(windowHasEnoughRecord(30, 0), isTrue);
    });
    test('long windows need ~60% of the span logged as record age', () {
      expect(windowHasEnoughRecord(90, 53), isFalse);
      expect(windowHasEnoughRecord(90, 54), isTrue);
      expect(windowHasEnoughRecord(180, 107), isFalse);
      expect(windowHasEnoughRecord(180, 108), isTrue);
    });
  });

  group('velocityOverWindow — clinical validity floor', () {
    Map<String, dynamic> m(String date, double cm) =>
        {'recorded_date': date, 'stature_height_cm': cm};
    final now = DateTime(2026, 7, 28);

    test('computes cm/yr from the window endpoints', () {
      // Newest-first, like AppState.measurements. 169 days apart,
      // 2.8 cm gained → ~6.05 cm/yr.
      final v = velocityOverWindow(
        [m('2026-07-20', 121.0), m('2026-02-01', 118.2)],
        180,
        now: now,
      );
      expect(v, isNotNull);
      expect(v!, closeTo(2.8 / 169 * 365.25, 0.01));
    });

    test('refuses a pair spanning under 3 months — noise, not velocity',
        () {
      final v = velocityOverWindow(
        [m('2026-07-20', 121.0), m('2026-06-01', 120.5)],
        180,
        now: now,
      );
      expect(v, isNull);
    });

    test('ignores measurements outside the window', () {
      // The 2025 point would satisfy the span if it leaked in.
      final v = velocityOverWindow(
        [m('2026-07-20', 121.0), m('2025-01-01', 110.0)],
        180,
        now: now,
      );
      expect(v, isNull);
    });

    test('needs two distinct points', () {
      expect(
          velocityOverWindow([m('2026-07-20', 121.0)], 180, now: now), isNull);
      expect(velocityOverWindow([], 180, now: now), isNull);
    });
  });
}
