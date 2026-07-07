// ══════════════════════════════════════════════════════════════════
// AppState — Flutter counterpart of the PWA's global APP object.
// Same shape of state (children, activeChild index, logDate, per-day
// data), exposed as a ChangeNotifier so screens rebuild on change.
// Talks to the SAME Supabase tables as app.js; nothing here writes
// yet — the first prototype is read-only over the day's data.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local-calendar-day ISO string (YYYY-MM-DD). Deliberately NOT
/// DateTime.toIso8601String().split('T') — that would be UTC and
/// shift the date before 7:00 in Bangkok. Same rule as CLAUDE.md.
String localISO(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String todayISO() => localISO(DateTime.now());

class AppState extends ChangeNotifier {
  final SupabaseClient sb;
  AppState(this.sb);

  List<Map<String, dynamic>> children = [];
  int activeChild = 0;
  String logDate = todayISO();

  // Per-day data for the active child + logDate
  Map<String, dynamic>? nutrition; // daily_nutrition row
  Map<String, dynamic>? sleep; // daily_sleep row
  List<Map<String, dynamic>> activityItems = []; // daily_activity_items rows
  List<Map<String, dynamic>> nutritionLogItems = []; // nutrition_log_items rows

  // measurements rows for the active child, newest first (per-child,
  // not per-logDate — reloaded on child switch)
  List<Map<String, dynamic>> measurements = [];

  /// Dates (YYYY-MM-DD) in the current Mon–Sun week that have any log
  /// — feeds the consistency card. Refreshed with loadDay.
  Set<String> weekLogDates = {};

  /// Which meal new food logs get tagged with — defaults to breakfast,
  /// same as the PWA's activeMealSlot.
  String activeMealSlot = 'breakfast';

  bool loadingChildren = false;
  bool loadingDay = false;
  String? lastError;

  Map<String, dynamic>? get activeChildRow =>
      (activeChild >= 0 && activeChild < children.length)
          ? children[activeChild]
          : null;

  String? get activeChildId => activeChildRow?['child_id'] as String?;

  Future<void> loadChildren() async {
    loadingChildren = true;
    lastError = null;
    notifyListeners();
    try {
      final rows = await sb
          .from('children')
          .select()
          .eq('status', 'active')
          .order('created_at', ascending: true);
      children = List<Map<String, dynamic>>.from(rows);
      if (activeChild >= children.length) activeChild = 0;
    } on PostgrestException catch (e) {
      lastError = e.message;
      children = [];
    }
    loadingChildren = false;
    notifyListeners();
    await Future.wait(
        [loadDay(), loadMeasurements(), loadWeekConsistency()]);
  }

  Future<void> setActiveChild(int i) async {
    if (i == activeChild) return;
    activeChild = i;
    notifyListeners();
    await Future.wait(
        [loadDay(), loadMeasurements(), loadWeekConsistency()]);
  }

  Future<void> setLogDate(String date) async {
    if (date == logDate) return;
    logDate = date;
    notifyListeners();
    await loadDay();
  }

  Future<void> shiftLogDate(int days) async {
    final parts = logDate.split('-').map(int.parse).toList();
    final d = DateTime(parts[0], parts[1], parts[2]).add(Duration(days: days));
    await setLogDate(localISO(d));
  }

  Future<void> loadDay() async {
    final childId = activeChildId;
    if (childId == null) {
      nutrition = null;
      sleep = null;
      activityItems = [];
      nutritionLogItems = [];
      notifyListeners();
      return;
    }
    loadingDay = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        sb
            .from('daily_nutrition')
            .select()
            .eq('child_id', childId)
            .eq('log_date', logDate)
            .maybeSingle(),
        sb
            .from('daily_sleep')
            .select()
            .eq('child_id', childId)
            .eq('log_date', logDate)
            .maybeSingle(),
        sb
            .from('daily_activity_items')
            .select()
            .eq('child_id', childId)
            .eq('log_date', logDate)
            .order('created_at', ascending: true),
        sb
            .from('nutrition_log_items')
            .select()
            .eq('child_id', childId)
            .eq('log_date', logDate)
            .order('logged_at', ascending: true),
      ]);
      nutrition = results[0] as Map<String, dynamic>?;
      sleep = results[1] as Map<String, dynamic>?;
      activityItems =
          List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      nutritionLogItems =
          List<Map<String, dynamic>>.from(results[3] as List? ?? []);
      lastError = null;
    } on PostgrestException catch (e) {
      lastError = e.message;
    }
    loadingDay = false;
    notifyListeners();
  }

  void setMealSlot(String slot) {
    activeMealSlot = slot;
    notifyListeners();
  }

  /// Mirror of the PWA's recordNutritionLogItem() — one row per tap,
  /// per-serving amounts, reviewable and undoable. daily_nutrition
  /// totals are NOT written here; the PWA's save flow recomputes them
  /// from these rows, so items logged in Flutter show up there too.
  Future<String?> recordNutritionLogItem({
    required String foodId,
    required String foodName,
    required double proteinG,
    double? zincMg,
    double? calciumMg,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    try {
      final row = await sb
          .from('nutrition_log_items')
          .insert({
            'child_id': childId,
            'log_date': logDate,
            'meal_slot': activeMealSlot,
            'food_id': foodId,
            'food_name': foodName,
            'protein_g': proteinG,
            'zinc_mg': zincMg,
            'calcium_mg': calciumMg,
            'created_by': sb.auth.currentUser?.id,
          })
          .select()
          .single();
      nutritionLogItems.add(row);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> deleteNutritionLogItem(dynamic itemId) async {
    try {
      await sb.from('nutrition_log_items').delete().eq('item_id', itemId);
      nutritionLogItems.removeWhere((i) => i['item_id'] == itemId);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Mirror of the PWA's confirmLogActivity() insert. duration_min is
  /// the readiness-score normalization: reps count 0.25 min each.
  Future<String?> recordActivityItem({
    required String activityId,
    required String displayName,
    required String category,
    required String tier,
    required int rawValue,
    required String unit,
    required bool isOutdoor,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    final durationMin = unit == 'reps' ? rawValue * 0.25 : rawValue.toDouble();
    try {
      final row = await sb
          .from('daily_activity_items')
          .insert({
            'child_id': childId,
            'log_date': logDate,
            'activity_id': activityId,
            'display_name': displayName,
            'category': category,
            'tier': tier,
            'duration_min': durationMin,
            'duration_value': rawValue,
            'unit': unit,
            'is_outdoor': isOutdoor,
            'is_custom': false,
          })
          .select()
          .single();
      activityItems.add(row);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> deleteActivityItem(dynamic itemId) async {
    try {
      await sb.from('daily_activity_items').delete().eq('item_id', itemId);
      activityItems.removeWhere((i) => i['item_id'] == itemId);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Any log (food item, sleep, activity) marks the day as logged —
  /// same signal the PWA's consistency row uses.
  Future<void> loadWeekConsistency() async {
    final childId = activeChildId;
    if (childId == null) {
      weekLogDates = {};
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final monday =
        localISO(now.subtract(Duration(days: (now.weekday - 1) % 7)));
    try {
      final results = await Future.wait([
        sb
            .from('nutrition_log_items')
            .select('log_date')
            .eq('child_id', childId)
            .gte('log_date', monday),
        sb
            .from('daily_sleep')
            .select('log_date')
            .eq('child_id', childId)
            .gte('log_date', monday),
        sb
            .from('daily_activity_items')
            .select('log_date')
            .eq('child_id', childId)
            .gte('log_date', monday),
      ]);
      weekLogDates = {
        for (final rows in results)
          for (final r in rows as List) r['log_date'] as String,
      };
    } on PostgrestException {
      // Consistency is decorative — never block the Today screen on it.
    }
    notifyListeners();
  }

  /// Mirror of the PWA's daily_sleep upsert in saveTodayData():
  /// total from bed→wake across midnight; efficiency = duration
  /// adequacy vs the 9.5h target.
  Future<String?> saveSleep({
    required String bedtime, // 'HH:mm'
    required String wakeTime, // 'HH:mm'
    required int nightWakes,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    final bed = bedtime.split(':').map(int.parse).toList();
    final wake = wakeTime.split(':').map(int.parse).toList();
    final bedMins = bed[0] * 60 + bed[1];
    var wakeMins = wake[0] * 60 + wake[1];
    if (bedMins > wakeMins) wakeMins += 1440;
    final totalSleepMin = wakeMins - bedMins;
    final efficiency =
        ((totalSleepMin / (9.5 * 60)) * 100).round().clamp(0, 100);
    try {
      await sb.from('daily_sleep').upsert({
        'child_id': childId,
        'log_date': logDate,
        'total_sleep_min': totalSleepMin,
        'sleep_efficiency_score': efficiency,
        'night_wakes': nightWakes,
        'bedtime': bedtime,
        'wake_time': wakeTime,
        'data_source': 'manual',
      }, onConflict: 'child_id,log_date');
      await loadDay();
      loadWeekConsistency();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<void> loadMeasurements() async {
    final childId = activeChildId;
    if (childId == null) {
      measurements = [];
      notifyListeners();
      return;
    }
    try {
      final rows = await sb
          .from('measurements')
          .select('measurement_id, recorded_date, stature_height_cm, mass_weight_kg')
          .eq('child_id', childId)
          .order('recorded_date', ascending: false);
      measurements = List<Map<String, dynamic>>.from(rows);
    } on PostgrestException catch (e) {
      lastError = e.message;
    }
    notifyListeners();
  }

  /// Mirror of the PWA's addMeasurement() — upsert on
  /// child_id+recorded_date; calculated_bmi is a generated column,
  /// never sent.
  Future<String?> addMeasurement({
    required String date,
    required double heightCm,
    required double weightKg,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    try {
      await sb.from('measurements').upsert({
        'child_id': childId,
        'recorded_date': date,
        'stature_height_cm': heightCm,
        'mass_weight_kg': weightKg,
        'data_source': 'manual',
      }, onConflict: 'child_id,recorded_date');
      await loadMeasurements();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> deleteMeasurement(dynamic measurementId) async {
    try {
      await sb
          .from('measurements')
          .delete()
          .eq('measurement_id', measurementId);
      measurements.removeWhere((m) => m['measurement_id'] == measurementId);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  void reset() {
    children = [];
    activeChild = 0;
    logDate = todayISO();
    nutrition = null;
    sleep = null;
    activityItems = [];
    nutritionLogItems = [];
    measurements = [];
    activeMealSlot = 'breakfast';
    notifyListeners();
  }
}
