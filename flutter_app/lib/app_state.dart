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

  /// The signed-in parent's user_accounts row — subscription tier,
  /// free-tier usage counters. Loaded once with the children.
  Map<String, dynamic>? account;

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

  // Clinical records for the active child — lazy-loaded when the
  // Medical tab first needs them, then kept in sync by the CRUD
  // methods below. Same tables the PWA's clinical log writes.
  List<Map<String, dynamic>> boneAgeAssessments = [];
  List<Map<String, dynamic>> labResults = [];
  List<Map<String, dynamic>> illnessEvents = [];
  List<Map<String, dynamic>> pubertyEvents = [];
  String? _clinicalLoadedFor; // childId the lists were fetched for
  bool loadingClinical = false;

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

  Future<void> loadAccount() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      account = await sb
          .from('user_accounts')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      notifyListeners();
    } on PostgrestException {
      // Non-fatal — subscription card just shows defaults.
    }
  }

  Future<void> loadChildren() async {
    loadingChildren = true;
    lastError = null;
    notifyListeners();
    loadAccount();
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
    _clinicalLoadedFor = null; // clinical lists are per-child
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

  /// Mirror of the PWA's daily_nutrition upsert in saveTodayData().
  /// Per-meal protein = item sums by slot; any manual gap between the
  /// edited total and what the log accounts for is attributed to the
  /// selected meal slot; snack folds into dinner for storage (the
  /// items keep the real snack tag).
  Future<String?> saveNutrition({
    required double proteinTotalG,
    required double calciumMg,
    required double zincMg,
    required int waterGlasses,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';

    final mealSums = {
      'breakfast': 0.0, 'lunch': 0.0, 'dinner': 0.0, 'snack': 0.0,
    };
    for (final item in nutritionLogItems) {
      final slot = item['meal_slot'] as String? ?? 'breakfast';
      mealSums[mealSums.containsKey(slot) ? slot : 'breakfast'] =
          (mealSums[mealSums.containsKey(slot) ? slot : 'breakfast'] ?? 0) +
              ((item['protein_g'] as num?)?.toDouble() ?? 0);
    }
    final itemsTotal =
        mealSums.values.fold<double>(0, (a, b) => a + b);
    final manualGap = proteinTotalG - itemsTotal;
    if (manualGap > 0) {
      final slot =
          mealSums.containsKey(activeMealSlot) ? activeMealSlot : 'breakfast';
      mealSums[slot] = mealSums[slot]! + manualGap;
    }
    mealSums['dinner'] = mealSums['dinner']! + mealSums['snack']!;

    double r1(double v) => (v * 10).roundToDouble() / 10;
    try {
      await sb.from('daily_nutrition').upsert({
        'child_id': childId,
        'log_date': logDate,
        'protein_breakfast_g': r1(mealSums['breakfast']!),
        'protein_lunch_g': r1(mealSums['lunch']!),
        'protein_dinner_g': r1(mealSums['dinner']!),
        'calcium_mg': calciumMg.round(),
        'zinc_mg': r1(zincMg),
        'fluids_ml': waterGlasses * 250, // 1 glass ≈ 250ml
      }, onConflict: 'child_id,log_date');
      await loadDay();
      loadWeekConsistency();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Update editable child-profile fields (name, DOB, parent heights
  /// and ages — the same columns the PWA's account screen writes).
  Future<String?> updateChild(
      dynamic childId, Map<String, dynamic> fields) async {
    try {
      await sb.from('children').update(fields).eq('child_id', childId);
      final i = children.indexWhere((c) => c['child_id'] == childId);
      if (i >= 0) children[i] = {...children[i], ...fields};
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<void> loadClinicalIfNeeded() async {
    final childId = activeChildId;
    if (childId == null || childId == _clinicalLoadedFor) return;
    _clinicalLoadedFor = childId;
    loadingClinical = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        sb
            .from('bone_age_assessments')
            .select()
            .eq('child_id', childId)
            .order('study_date', ascending: false),
        sb
            .from('lab_results')
            .select()
            .eq('child_id', childId)
            .order('lab_date', ascending: false),
        sb
            .from('illness_events')
            .select()
            .eq('child_id', childId)
            .order('start_date', ascending: false),
        sb
            .from('puberty_events')
            .select()
            .eq('child_id', childId)
            .order('event_date', ascending: false),
      ]);
      boneAgeAssessments = List<Map<String, dynamic>>.from(results[0]);
      labResults = List<Map<String, dynamic>>.from(results[1]);
      illnessEvents = List<Map<String, dynamic>>.from(results[2]);
      pubertyEvents = List<Map<String, dynamic>>.from(results[3]);
    } on PostgrestException catch (e) {
      lastError = e.message;
      _clinicalLoadedFor = null; // retry on next open
    }
    loadingClinical = false;
    notifyListeners();
  }

  Future<String?> _insertClinical(String table, Map<String, dynamic> row,
      List<Map<String, dynamic>> list) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    try {
      final saved = await sb
          .from(table)
          .insert({
            'child_id': childId,
            'created_by': sb.auth.currentUser?.id,
            ...row,
          })
          .select()
          .single();
      list.insert(0, saved);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> _deleteClinical(String table, String idColumn, dynamic id,
      List<Map<String, dynamic>> list) async {
    try {
      await sb.from(table).delete().eq(idColumn, id);
      list.removeWhere((r) => r[idColumn] == id);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> addBoneAge({
    required String studyDate,
    required int boneAgeMonths,
    double? sdMonths,
    required String method,
    required double chronologicalAgeMonths,
    String? reportDoctor,
    String? notes,
  }) =>
      _insertClinical('bone_age_assessments', {
        'study_date': studyDate,
        'bone_age_months': boneAgeMonths,
        'sd_months': sdMonths,
        'method': method,
        'chronological_age_months': chronologicalAgeMonths,
        'report_doctor': reportDoctor,
        'notes': notes,
      }, boneAgeAssessments);

  Future<String?> deleteBoneAge(dynamic id) => _deleteClinical(
      'bone_age_assessments', 'assessment_id', id, boneAgeAssessments);

  Future<String?> addLabResult({
    required String labDate,
    required String analyteName,
    required double resultValue,
    required String unit,
    double? referenceLow,
    double? referenceHigh,
  }) =>
      _insertClinical('lab_results', {
        'lab_date': labDate,
        'analyte_name': analyteName,
        'result_value': resultValue,
        'unit': unit,
        'reference_low': referenceLow,
        'reference_high': referenceHigh,
      }, labResults);

  Future<String?> deleteLabResult(dynamic id) =>
      _deleteClinical('lab_results', 'lab_result_id', id, labResults);

  Future<String?> addIllnessEvent({
    required String startDate,
    String? endDate,
    required String illnessType,
    String? notes,
  }) =>
      _insertClinical('illness_events', {
        'start_date': startDate,
        'end_date': endDate,
        'illness_type': illnessType,
        'notes': notes,
      }, illnessEvents);

  Future<String?> deleteIllnessEvent(dynamic id) =>
      _deleteClinical('illness_events', 'event_id', id, illnessEvents);

  Future<String?> addPubertyEvent({
    required String eventDate,
    required String eventType,
    int? tannerStage,
  }) =>
      _insertClinical('puberty_events', {
        'event_date': eventDate,
        'event_type': eventType,
        'tanner_stage': tannerStage,
      }, pubertyEvents);

  Future<String?> deletePubertyEvent(dynamic id) =>
      _deleteClinical('puberty_events', 'event_id', id, pubertyEvents);

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
    boneAgeAssessments = [];
    labResults = [];
    illnessEvents = [];
    pubertyEvents = [];
    _clinicalLoadedFor = null;
    weekLogDates = {};
    activeMealSlot = 'breakfast';
    notifyListeners();
  }
}
