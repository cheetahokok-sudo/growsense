import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/coach_digest.dart';
import 'package:growsense/food_data.dart';

FoodItem _food(String id, String name, String category,
        {double servingGrams = 30, double proteinPer100g = 25}) =>
    FoodItem.fromJson({
      'id': id,
      'name': name,
      'emoji': '🍽️',
      'category': category,
      'per100g': {'protein_g': proteinPer100g},
      'servingGrams': servingGrams,
    });

final _salmon = _food('salmon', 'Salmon', 'fish');
final _mackerel = _food('mackerel', 'Mackerel', 'fish');
final _egg = _food('egg', 'Egg', 'egg', servingGrams: 50);
final _foods = [_salmon, _mackerel, _egg];
final _byId = {for (final f in _foods) f.id: f};

Map<String, dynamic> _item(String date, String? foodId, String name, num p) =>
    {'log_date': date, 'food_id': foodId, 'food_name': name, 'protein_g': p};

Map<String, dynamic> _day(String date, num protein, [String? method]) => {
      'log_date': date,
      'total_protein_g': protein,
      'estimation_method': method,
    };

void main() {
  group('resolveCoachWindowDays', () {
    test('default is 30, phrases resolve, everything clamps to 365', () {
      expect(resolveCoachWindowDays('how much salmon?'), 30);
      expect(resolveCoachWindowDays('since last month'), 30);
      expect(resolveCoachWindowDays('this week'), 7);
      expect(resolveCoachWindowDays('past 2 weeks'), 14);
      expect(resolveCoachWindowDays('last 3 months'), 90);
      expect(resolveCoachWindowDays('over the last year'), 365);
      // The scenario from the load audit: 10 years clamps, never scans.
      expect(resolveCoachWindowDays('protein for the last 10 years'), 365);
      expect(resolveCoachWindowDays('last 2 days'), 7); // floor
    });

    test('Thai time phrases resolve', () {
      expect(resolveCoachWindowDays('กินแซลมอนไปเท่าไหร่เดือนที่แล้ว'), 30);
      expect(resolveCoachWindowDays('2 สัปดาห์ที่ผ่านมา'), 14);
      expect(resolveCoachWindowDays('10 ปีที่ผ่านมา'), 365);
    });
  });

  group('scanCoachQuestion', () {
    test('matches an English food name', () {
      final s = scanCoachQuestion('How much salmon has Peem eaten?', _foods);
      expect(s.foodIds, ['salmon']);
      expect(s.nutritionRelated, isTrue);
      expect(s.wantsFish, isTrue); // salmon is a fish → omega context
    });

    test('matches Thai aliases, most specific wins', () {
      final s = scanCoachQuestion('ลูกกินปลาแซลมอนเยอะไหม', _foods);
      expect(s.foodIds, ['salmon']);
      // ปลาทูน่า must not fall through to ปลาทู (mackerel).
      final t = scanCoachQuestion('กินปลาทูบ่อยแค่ไหน', _foods);
      expect(t.foodIds, ['mackerel']);
    });

    test('generic fish question wants the fish breakdown', () {
      final s = scanCoachQuestion('Is he getting enough DHA?', _foods);
      expect(s.foodIds, isEmpty);
      expect(s.wantsFish, isTrue);
      expect(s.nutritionRelated, isTrue);
    });

    test('nutrition keywords without a food still attach a digest', () {
      final s = scanCoachQuestion('Was his protein enough last month?', _foods);
      expect(s.nutritionRelated, isTrue);
      expect(s.foodIds, isEmpty);
    });

    test('non-food question attaches nothing', () {
      final s = scanCoachQuestion('Why is sleep important for growth?', _foods);
      expect(s.nutritionRelated, isFalse);
    });
  });

  group('buildFoodDigest', () {
    final today = DateTime(2026, 8, 1);

    test('serving math: taps × servingGrams, share of logged protein', () {
      final scan = scanCoachQuestion('salmon since last month', _foods);
      final items = [
        for (var i = 0; i < 9; i++)
          _item('2026-07-${(i + 1).toString().padLeft(2, '0')}', 'salmon',
              'Salmon', 7.62),
        _item('2026-07-10', 'egg', 'Egg', 6.3),
      ];
      final days = [
        for (var i = 0; i < 21; i++)
          _day('2026-07-${(i + 1).toString().padLeft(2, '0')}',
              i < 21 ? 23.3 : 0, 'measured'),
      ];
      final d = buildFoodDigest(
        scan: scan,
        itemRows: items,
        dailyRows: days,
        foodsById: _byId,
        today: today,
        proteinTargetG: 28,
      );
      expect(d, contains('WINDOW 2026-07-03 -> 2026-08-01'));
      expect(d, contains('21 with food logs'));
      expect(d, contains('Salmon: 9 servings ~270 g'));
      expect(d, contains('protein 68.6 g'));
      expect(d, contains('% of logged protein'));
      expect(d, contains('avg 23.3 g/day'));
    });

    test('estimated days are excluded from the denominator', () {
      final scan = scanCoachQuestion('salmon protein', _foods);
      final items = [_item('2026-07-30', 'salmon', 'Salmon', 10)];
      final days = [
        _day('2026-07-30', 20, 'measured'),
        _day('2026-07-29', 100, 'pattern_fill'), // phantom protein
        _day('2026-07-28', 100, 'relative_recall'),
      ];
      final d = buildFoodDigest(
        scan: scan,
        itemRows: items,
        dailyRows: days,
        foodsById: _byId,
        today: today,
      );
      // 10/20 = 50%; with estimated rows included it would be 10/220.
      expect(d, contains('(50% of logged protein)'));
      expect(d, contains('1 with food logs'));
    });

    test('a null estimation_method counts as measured (pre-migration rows)',
        () {
      final scan = scanCoachQuestion('protein last week', _foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: [_item('2026-07-30', 'egg', 'Egg', 6.3)],
        dailyRows: [_day('2026-07-30', 6.3)],
        foodsById: _byId,
        today: today,
      );
      expect(d, contains('total 6.3 g'));
    });

    test('asked-about food with no entries says so honestly', () {
      final scan = scanCoachQuestion('how much mackerel did he eat?', _foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: [_item('2026-07-30', 'egg', 'Egg', 6.3)],
        dailyRows: [_day('2026-07-30', 6.3, 'measured')],
        foodsById: _byId,
        today: today,
      );
      expect(d, contains('Mackerel: no entries in this window'));
    });

    test('custom foods aggregate by name with grams unknown', () {
      final scan = scanCoachQuestion('protein this week', _foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: [
          _item('2026-07-30', null, 'Grandma soup', 6),
          _item('2026-07-31', null, 'Grandma soup', 6),
        ],
        dailyRows: [
          _day('2026-07-30', 6, 'measured'),
          _day('2026-07-31', 6, 'measured'),
        ],
        foodsById: _byId,
        today: today,
      );
      expect(d, contains('Grandma soup: 2 servings serving size unknown'));
      expect(d, contains('protein 12.0 g'));
    });

    test('fish breakdown appears for omega questions', () {
      final scan = scanCoachQuestion('enough omega-3?', _foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: [
          _item('2026-07-30', 'salmon', 'Salmon', 7.6),
          _item('2026-07-29', 'mackerel', 'Mackerel', 5.6),
          _item('2026-07-29', 'egg', 'Egg', 6.3),
        ],
        dailyRows: [
          _day('2026-07-30', 10, 'measured'),
          _day('2026-07-29', 12, 'measured'),
        ],
        foodsById: _byId,
        today: today,
      );
      expect(d, contains('All fish & seafood in the window'));
      expect(d, contains('Salmon'));
      expect(d, contains('Mackerel'));
    });

    test('empty log stays honest and the digest stays under its cap', () {
      final scan = scanCoachQuestion('what did he eat last year?', _foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: const [],
        dailyRows: const [],
        foodsById: _byId,
        today: today,
      );
      expect(d, contains('No food items logged in this window.'));
      expect(d.length, lessThanOrEqualTo(kDigestMaxChars));
    });
  });

  group('coach prompt budget', () {
    test('worst-case digest fits the proxy system cap alongside the prompt',
        () {
      // 40 distinct foods, all logged heavily — far beyond any real
      // child — must still respect kDigestMaxChars (the proxy caps
      // system at 8000 chars; the base prompt is ~1.7k).
      final foods = [
        for (var i = 0; i < 40; i++)
          _food('f$i', 'Some Very Long Food Name Number $i', 'fish'),
      ];
      final scan = scanCoachQuestion('enough omega-3 fish last year?', foods);
      final d = buildFoodDigest(
        scan: scan,
        itemRows: [
          for (var i = 0; i < 40; i++)
            for (var j = 0; j < 5; j++)
              _item('2026-07-0${(j % 9) + 1}', 'f$i',
                  'Some Very Long Food Name Number $i', 7),
        ],
        dailyRows: [
          for (var j = 1; j <= 9; j++) _day('2026-07-0$j', 140, 'measured'),
        ],
        foodsById: {for (final f in foods) f.id: f},
        today: DateTime(2026, 8, 1),
      );
      expect(d.length, lessThanOrEqualTo(kDigestMaxChars));
    });
  });
}
