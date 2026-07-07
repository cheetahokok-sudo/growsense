import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/growth_math.dart';

void main() {
  test('zFromHeight and heightAtZ are inverses on the bands', () {
    final bands = [110.0, 114.0, 119.0, 124.0, 128.0]; // p3..p97
    for (final h in [111.0, 116.5, 119.0, 122.0, 127.0]) {
      final z = zFromHeight(bands, h);
      expect(heightAtZ(bands, z), closeTo(h, 0.001));
    }
  });

  test('interpolateBands is exact on rows and linear between', () {
    final table = [
      [60.0, 100.0, 104.0, 108.0, 112.0, 116.0],
      [72.0, 106.0, 110.0, 114.0, 118.0, 122.0],
    ];
    expect(interpolateBands(table, 60), equals([100, 104, 108, 112, 116]));
    expect(interpolateBands(table, 66)[2], closeTo(111.0, 0.001));
    // Clamped outside range
    expect(interpolateBands(table, 300)[0], equals(106));
  });

  test('target height matches the verified live value (Peem)', () {
    // mother 156 cm / father 173 cm, both age 40, male child —
    // verified against the running app: 172.2 cm (167.7–176.7).
    final t = calculateTargetHeight(
      motherHeightCm: 156,
      fatherHeightCm: 173,
      motherAge: 40,
      fatherAge: 40,
      childSex: 'male',
    )!;
    expect(t.targetHeightCm, closeTo(172.2, 0.1));
    expect(t.rangeLowCm, closeTo(167.7, 0.1));
    expect(t.rangeHighCm, closeTo(176.7, 0.1));
    expect(t.tannerMidParentalCm, closeTo(171.0, 0.05));
  });

  test('projection lands on the destination channel at the horizon', () {
    final table = [
      for (var m = 61; m <= 228; m += 6)
        [
          m.toDouble(),
          100 + (m - 61) * 0.25,
          104 + (m - 61) * 0.25,
          108 + (m - 61) * 0.25,
          112 + (m - 61) * 0.25,
          116 + (m - 61) * 0.25,
        ],
    ];
    final startBands = interpolateBands(table, 8 * 12);
    final startH = heightAtZ(startBands, -1.0);
    final pts = projectGrowth(
      table: table,
      currentAgeYears: 8,
      currentHeightCm: startH,
      targetZ: 0.5,
    );
    final endBands = interpolateBands(table, pts.last.ageYears * 12);
    expect(zFromHeight(endBands, pts.last.heightCm), closeTo(0.5, 0.01));
  });

  test('readiness nudge is small and capped', () {
    final table = [
      [61.0, 100.0, 104.0, 108.0, 112.0, 116.0],
      [228.0, 140.0, 144.0, 148.0, 152.0, 156.0],
    ];
    final bands = interpolateBands(table, 10 * 12);
    final h = heightAtZ(bands, 0);
    final neutral = projectGrowth(
        table: table, currentAgeYears: 10, currentHeightCm: h,
        targetZ: 0, readinessScore: 50);
    final best = projectGrowth(
        table: table, currentAgeYears: 10, currentHeightCm: h,
        targetZ: 0, readinessScore: 100);
    final endBands = interpolateBands(table, neutral.last.ageYears * 12);
    final zNeutral = zFromHeight(endBands, neutral.last.heightCm);
    final zBest = zFromHeight(endBands, best.last.heightCm);
    expect(zBest - zNeutral, closeTo(0.15, 0.01));
  });
}
