// ══════════════════════════════════════════════════════════════════
// AppState — Flutter counterpart of the PWA's global APP object.
// Same shape of state (children, activeChild index, logDate, per-day
// data), exposed as a ChangeNotifier so screens rebuild on change.
// Talks to the SAME Supabase tables as app.js; nothing here writes
// yet — the first prototype is read-only over the day's data.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics.dart' show calcSleepTargetMin;
import 'app_meta.dart';
import 'recall_engine.dart' show manualEntryMeta;

/// Downscale an X-ray to <=800px JPEG for AI vision analysis — same
/// 800px/0.85 rule as the PWA's canvas downscale. Top-level so it can
/// run through compute() off the UI thread (no-op isolate on web).
Uint8List downscaleXrayJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  const maxDim = 800;
  img.Image out = decoded;
  if (decoded.width > maxDim || decoded.height > maxDim) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxDim)
        : img.copyResize(decoded, height: maxDim);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

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

  /// google_health_connection_status row for the active child (Fitbit /
  /// Google Health), or null if not connected. Read-only safe view —
  /// no tokens. Reused by the Devices screen.
  Map<String, dynamic>? wearableStatus;
  String? _wearableLoadedFor;
  bool syncingWearable = false;

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
    final user = sb.auth.currentUser;
    if (user == null) return;
    try {
      account = await sb
          .from('user_accounts')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      // First entry via Google/Apple OAuth (or a partial email
      // signup): there is no DB trigger for user_accounts — the PWA
      // inserts it client-side after signUp — so self-heal here.
      // Flutter onboards parents; clinicians sign up in the web app.
      account ??= await sb
          .from('user_accounts')
          .insert({
            'user_id': user.id,
            'email': user.email,
            'account_role': 'parent',
          })
          .select()
          .single();
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
    await Future.wait([loadDay(), loadMeasurements(), loadWeekConsistency()]);
  }

  Future<void> setActiveChild(int i) async {
    if (i == activeChild) return;
    activeChild = i;
    _clinicalLoadedFor = null; // clinical lists are per-child
    _wearableLoadedFor = null;
    notifyListeners();
    await Future.wait([loadDay(), loadMeasurements(), loadWeekConsistency()]);
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
      activityItems = List<Map<String, dynamic>>.from(
        results[2] as List? ?? [],
      );
      nutritionLogItems = List<Map<String, dynamic>>.from(
        results[3] as List? ?? [],
      );
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
    double? ironMg,
    double? vitaminDIu,
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
            // Minor co-factors — auto-captured, Analytics-only.
            'iron_mg': ironMg,
            'vitamin_d_iu': vitaminDIu,
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

  // ── Custom foods — parent-defined foods, per child (mirror of the
  // PWA's custom_foods flow). Values are stored for THE serving, not
  // per-100g. Loaded on the Food tab; merged into the browse list.
  List<Map<String, dynamic>> customFoods = [];

  Future<void> loadCustomFoods() async {
    final childId = activeChildId;
    if (childId == null) {
      customFoods = [];
      notifyListeners();
      return;
    }
    try {
      final rows = await sb
          .from('custom_foods')
          .select('*')
          .eq('child_id', childId)
          .order('created_at', ascending: false);
      customFoods = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      customFoods = [];
    }
    notifyListeners();
  }

  /// Custom-food cap: keeps "Mine" curated and blocks garbage growth.
  /// Storage is a non-issue (~200 bytes/row) — this is a UX/abuse cap
  /// and a natural free/premium boundary, mirroring addChild's gating.
  int get customFoodLimit =>
      ((account?['subscription_tier'] as String?) ?? 'free') == 'free' ? 5 : 50;

  Future<String?> addCustomFood({
    required String name,
    required double servingGrams,
    String? description,
    required double proteinG,
    double? zincMg,
    double? calciumMg,
  }) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    final limit = customFoodLimit;
    if (customFoods.length >= limit) {
      final tier = (account?['subscription_tier'] as String?) ?? 'free';
      return tier == 'free'
          ? 'Free plan supports up to $limit custom foods — remove one or upgrade'
          : 'Your plan supports up to $limit custom foods — remove one first';
    }
    try {
      final row = await sb
          .from('custom_foods')
          .insert({
            'child_id': childId,
            'name': name,
            'serving_grams': servingGrams,
            'serving_description': description,
            'protein_g': proteinG,
            'zinc_mg': zincMg,
            'calcium_mg': calciumMg,
            'created_by': sb.auth.currentUser?.id,
          })
          .select()
          .single();
      customFoods = [row, ...customFoods];
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> updateCustomFood(
    dynamic customFoodId, {
    required String name,
    required double servingGrams,
    String? description,
    required double proteinG,
    double? zincMg,
    double? calciumMg,
  }) async {
    try {
      final row = await sb
          .from('custom_foods')
          .update({
            'name': name,
            'serving_grams': servingGrams,
            'serving_description': description,
            'protein_g': proteinG,
            'zinc_mg': zincMg,
            'calcium_mg': calciumMg,
          })
          .eq('custom_food_id', customFoodId)
          .select()
          .single();
      customFoods = [
        for (final r in customFoods)
          r['custom_food_id'] == customFoodId ? row : r,
      ];
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Deleting a custom food never touches history — nutrition_log_items
  /// snapshot their values at log time, so past days stay intact.
  Future<String?> deleteCustomFood(dynamic customFoodId) async {
    try {
      await sb.from('custom_foods').delete().eq('custom_food_id', customFoodId);
      customFoods = [
        for (final r in customFoods)
          if (r['custom_food_id'] != customFoodId) r,
      ];
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  // ── Food frequency — "the app learns me" ordering signal. Counts of
  // each food_id logged in the last 60 days. Recomputed at most once
  // per day per child (key includes today's date), so the list order
  // is stable within a day and never reshuffles mid-session.
  Map<String, int> foodLogCounts = {};
  String? _freqLoadedKey; // '<childId>|<date>'

  Future<void> loadFoodFrequency() async {
    final childId = activeChildId;
    if (childId == null) return;
    final key = '$childId|${todayISO()}';
    if (_freqLoadedKey == key) return;
    try {
      final since = localISO(DateTime.now().subtract(const Duration(days: 60)));
      final rows = await sb
          .from('nutrition_log_items')
          .select('food_id')
          .eq('child_id', childId)
          .gte('log_date', since)
          .limit(2000);
      final counts = <String, int>{};
      for (final r in rows) {
        final id = r['food_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      foodLogCounts = counts;
      _freqLoadedKey = key;
      notifyListeners();
    } catch (_) {
      // Non-fatal — list falls back to curated order.
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
            // Same manual-entry tiering as nutrition/sleep saves.
            'estimation_method': manualEntryMeta(logDate).method,
            'confidence': manualEntryMeta(logDate).confidence,
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
    final monday = localISO(
      now.subtract(Duration(days: (now.weekday - 1) % 7)),
    );
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
        ((totalSleepMin /
                    calcSleepTargetMin(
                      activeChildRow?['date_of_birth'] as String?,
                    )) *
                100)
            .round()
            .clamp(0, 100);
    try {
      final meta = manualEntryMeta(logDate);
      await sb.from('daily_sleep').upsert({
        'child_id': childId,
        'log_date': logDate,
        'total_sleep_min': totalSleepMin,
        'sleep_efficiency_score': efficiency,
        'night_wakes': nightWakes,
        'bedtime': bedtime,
        'wake_time': wakeTime,
        'data_source': 'manual',
        // Manual entry always wins over an estimate; trust tier is
        // inferred from how far back the night is.
        'estimation_method': meta.method,
        'confidence': meta.confidence,
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
      'breakfast': 0.0,
      'lunch': 0.0,
      'dinner': 0.0,
      'snack': 0.0,
    };
    for (final item in nutritionLogItems) {
      final slot = item['meal_slot'] as String? ?? 'breakfast';
      mealSums[mealSums.containsKey(slot) ? slot : 'breakfast'] =
          (mealSums[mealSums.containsKey(slot) ? slot : 'breakfast'] ?? 0) +
          ((item['protein_g'] as num?)?.toDouble() ?? 0);
    }
    final itemsTotal = mealSums.values.fold<double>(0, (a, b) => a + b);
    final manualGap = proteinTotalG - itemsTotal;
    if (manualGap > 0) {
      final slot = mealSums.containsKey(activeMealSlot)
          ? activeMealSlot
          : 'breakfast';
      mealSums[slot] = mealSums[slot]! + manualGap;
    }
    mealSums['dinner'] = mealSums['dinner']! + mealSums['snack']!;

    double r1(double v) => (v * 10).roundToDouble() / 10;
    // Manual entry always wins over any AI estimate; its trust tier is
    // inferred from how far back the day is (recall_engine's ladder) —
    // the parent is never asked "how sure are you?".
    final meta = manualEntryMeta(logDate);
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
        'estimation_method': meta.method,
        'confidence': meta.confidence,
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
    dynamic childId,
    Map<String, dynamic> fields,
  ) async {
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

  /// This account's archive-retention window (days). Read live from
  /// subscription_tier_limits — Pro keeps data longer — never hardcoded,
  /// so it can't silently drift from the documented policy. 365-day
  /// fallback if the lookup fails: never less protective than default.
  Future<int> archiveRetentionDays() async {
    final tier = (account?['subscription_tier'] as String?) ?? 'free';
    try {
      final row = await sb
          .from('subscription_tier_limits')
          .select('account_archive_retention_days')
          .eq('tier', tier)
          .maybeSingle();
      return (row?['account_archive_retention_days'] as num?)?.toInt() ?? 365;
    } catch (_) {
      return 365;
    }
  }

  /// Remove a child profile = soft-delete to archive (mirror of the PWA's
  /// deleteChildProfile). The row stays in the database with status
  /// 'archived' + a permanent_delete_after date; it's hidden everywhere
  /// active children are read, and recoverable until that date. Blocks
  /// removing the last active profile. Returns the retention window on
  /// success so the UI can say how long it's recoverable.
  Future<({String? error, int retentionDays})> archiveChild(
    dynamic childId,
  ) async {
    final activeCount = children.where((c) => c['status'] != 'archived').length;
    if (activeCount <= 1) {
      return (error: 'last_active', retentionDays: 0);
    }
    try {
      final days = await archiveRetentionDays();
      final now = DateTime.now().toUtc();
      final purge = now.add(Duration(days: days));
      await sb
          .from('children')
          .update({
            'status': 'archived',
            'archived_at': now.toIso8601String(),
            'archived_by': sb.auth.currentUser?.id,
            'permanent_delete_after': purge.toIso8601String(),
          })
          .eq('child_id', childId);
      // Drop from the in-memory active list and re-anchor the selection,
      // exactly like a fresh load would.
      children.removeWhere((c) => c['child_id'] == childId);
      if (activeChild >= children.length) activeChild = 0;
      _clinicalLoadedFor = null;
      _wearableLoadedFor = null;
      notifyListeners();
      await Future.wait([loadDay(), loadMeasurements(), loadWeekConsistency()]);
      return (error: null, retentionDays: days);
    } on PostgrestException catch (e) {
      return (error: e.message, retentionDays: 0);
    }
  }

  /// File an in-app bug/feedback report into the bug_reports table.
  /// Attaches version + an anonymized child snapshot (age/sex only) for
  /// triage. Returns null on success, an error string otherwise.
  Future<String?> submitBugReport({
    required String category,
    required String severity,
    required String description,
    required String locale,
    String? activeScreen,
  }) async {
    final child = activeChildRow;
    double? ageYears;
    final dob = child?['date_of_birth'] as String?;
    if (dob != null) {
      final d = DateTime.tryParse(dob);
      if (d != null) {
        ageYears = double.parse(
          (DateTime.now().difference(d).inDays / 365.25).toStringAsFixed(1),
        );
      }
    }
    try {
      await sb.from('bug_reports').insert({
        'user_id': sb.auth.currentUser?.id,
        'app_version': kAppVersion,
        'app_build': kAppBuild,
        'channel': kAppChannel,
        'locale': locale,
        'category': category,
        'severity': severity,
        'description': description,
        'child_age_years': ageYears,
        'child_sex': child?['biological_sex'],
        'context': activeScreen == null ? {} : {'active_screen': activeScreen},
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Reads the safe Fitbit/Google connection status view for the active
  /// child. Reuses the same backend the PWA connects through.
  Future<void> loadWearableStatus({bool force = false}) async {
    final childId = activeChildId;
    if (childId == null) {
      wearableStatus = null;
      notifyListeners();
      return;
    }
    if (!force && childId == _wearableLoadedFor) return;
    _wearableLoadedFor = childId;
    try {
      wearableStatus = await sb
          .from('google_health_connection_status')
          .select()
          .eq('child_id', childId)
          .maybeSingle();
    } on PostgrestException {
      wearableStatus = null;
    }
    notifyListeners();
  }

  /// Completes the Fitbit OAuth flow: hands the returned code to the
  /// google-health-auth Edge Function, which exchanges it for tokens
  /// server-side. Returns (connectedEmail, error).
  Future<(String?, String?)> connectFitbitWithCode(
    String code,
    String childId,
  ) async {
    try {
      final res = await sb.functions.invoke(
        'google-health-auth',
        body: {'code': code, 'child_id': childId},
      );
      final data = res.data as Map<String, dynamic>?;
      if (res.status != 200) {
        return (null, (data?['error'] as String?) ?? 'Connection failed');
      }
      await loadWearableStatus(force: true);
      return (data?['google_email'] as String?, null);
    } catch (e) {
      return (null, e.toString());
    }
  }

  /// Triggers the google-health-sync Edge Function to pull recent nights
  /// of Fitbit sleep (lands in daily_sleep with deep/rem/HRV columns).
  /// Returns the number of nights synced, or an error string.
  Future<(int?, String?)> syncFitbit({int daysBack = 14}) async {
    final childId = activeChildId;
    final token = sb.auth.currentSession?.accessToken;
    if (childId == null || token == null) return (null, 'Not signed in');
    syncingWearable = true;
    notifyListeners();
    try {
      final res = await sb.functions.invoke(
        'google-health-sync',
        body: {'child_id': childId, 'days_back': daysBack},
      );
      final data = res.data as Map<String, dynamic>?;
      syncingWearable = false;
      if (res.status != 200) {
        notifyListeners();
        return (null, _wearableSyncError(data));
      }
      await loadWearableStatus(force: true);
      await loadDay();
      return ((data?['nights_synced'] as num?)?.toInt() ?? 0, null);
    } on FunctionException catch (e) {
      // supabase_flutter throws on a non-2xx response; the real Google
      // OAuth error (invalid_client / invalid_grant / …) rides in details.
      syncingWearable = false;
      notifyListeners();
      final details = e.details;
      return (
        null,
        _wearableSyncError(
          details is Map ? details.cast<String, dynamic>() : null,
          fallback: 'Sync failed (${e.status})',
        ),
      );
    } catch (e) {
      syncingWearable = false;
      notifyListeners();
      return (null, e.toString());
    }
  }

  /// Turns an Edge Function / Google OAuth error body into a message.
  /// `invalid_grant` (dead refresh token) is user-fixable, so it gets an
  /// actionable line; anything else surfaces its raw code so an incident
  /// is self-diagnosing instead of a blank "Sync failed".
  String _wearableSyncError(Map<String, dynamic>? data,
      {String fallback = 'Sync failed'}) {
    final code =
        (data?['error'] ?? data?['error_description'] ?? data?['message'])
            ?.toString();
    if (code == null || code.isEmpty) return fallback;
    if (code.contains('invalid_grant')) {
      return 'Connection expired — reconnect Fitbit.';
    }
    // invalid_client / deleted_client / etc. — server-side, show raw.
    return code;
  }

  /// Removes the Fitbit/Google Health connection for the active child so a
  /// different Google account (or device) can be linked. Mirrors the PWA's
  /// disconnect: drops the connection row; sleep already synced stays.
  Future<String?> disconnectFitbit() async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    try {
      await sb
          .from('google_health_connections')
          .delete()
          .eq('child_id', childId);
      await loadWearableStatus(force: true);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
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

  Future<String?> _insertClinical(
    String table,
    Map<String, dynamic> row,
    List<Map<String, dynamic>> list,
  ) async {
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

  Future<String?> _deleteClinical(
    String table,
    String idColumn,
    dynamic id,
    List<Map<String, dynamic>> list,
  ) async {
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
    String? xrayStoragePath,
  }) => _insertClinical('bone_age_assessments', {
    'study_date': studyDate,
    'bone_age_months': boneAgeMonths,
    'sd_months': sdMonths,
    'method': method,
    'chronological_age_months': chronologicalAgeMonths,
    'report_doctor': reportDoctor,
    'notes': notes,
    'xray_storage_path': xrayStoragePath,
  }, boneAgeAssessments);

  // ── Data export ─────────────────────────────────────────────────────

  /// Assemble a CSV dossier for the active child: profile, growth
  /// measurements, clinical records, and the last 30 days of daily
  /// logs. Sections are stacked in one file with header rows — opens
  /// cleanly in Excel/Sheets and is easy to email to a clinician.
  Future<(String?, String?)> buildExportCsv() async {
    final child = activeChildRow;
    final childId = activeChildId;
    if (child == null || childId == null) return (null, 'No child selected');

    String cell(dynamic v) {
      final s = (v ?? '').toString();
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    String row(List<dynamic> cells) => cells.map(cell).join(',');

    try {
      await loadClinicalIfNeeded();
      final since = localISO(DateTime.now().subtract(const Duration(days: 30)));
      final results = await Future.wait([
        sb
            .from('daily_nutrition')
            .select('log_date, total_protein_g, calcium_mg, fluids_ml')
            .eq('child_id', childId)
            .gte('log_date', since)
            .order('log_date'),
        sb
            .from('daily_sleep')
            .select(
              'log_date, total_sleep_min, bedtime, wake_time,'
              ' night_wakes',
            )
            .eq('child_id', childId)
            .gte('log_date', since)
            .order('log_date'),
      ]);

      final b = StringBuffer()
        ..writeln('GrowSense data export,${todayISO()}')
        ..writeln()
        ..writeln('CHILD')
        ..writeln(row(['name', 'date_of_birth', 'biological_sex']))
        ..writeln(
          row([child['name'], child['date_of_birth'], child['biological_sex']]),
        )
        ..writeln()
        ..writeln('GROWTH MEASUREMENTS')
        ..writeln(row(['recorded_date', 'height_cm', 'weight_kg']));
      for (final m in measurements.reversed) {
        b.writeln(
          row([
            m['recorded_date'],
            m['stature_height_cm'],
            m['mass_weight_kg'],
          ]),
        );
      }

      b
        ..writeln()
        ..writeln('BONE AGE ASSESSMENTS')
        ..writeln(
          row([
            'study_date',
            'bone_age_months',
            'chronological_age_months',
            'method',
            'report_doctor',
          ]),
        );
      for (final r in boneAgeAssessments.reversed) {
        b.writeln(
          row([
            r['study_date'],
            r['bone_age_months'],
            r['chronological_age_months'],
            r['method'],
            r['report_doctor'],
          ]),
        );
      }

      b
        ..writeln()
        ..writeln('ILLNESS EVENTS')
        ..writeln(row(['start_date', 'end_date', 'illness_type', 'notes']));
      for (final e in illnessEvents.reversed) {
        b.writeln(
          row([e['start_date'], e['end_date'], e['illness_type'], e['notes']]),
        );
      }

      b
        ..writeln()
        ..writeln('LAB RESULTS')
        ..writeln(
          row([
            'lab_date',
            'analyte_name',
            'result_value',
            'unit',
            'reference_low',
            'reference_high',
          ]),
        );
      for (final l in labResults.reversed) {
        b.writeln(
          row([
            l['lab_date'],
            l['analyte_name'],
            l['result_value'],
            l['unit'],
            l['reference_low'],
            l['reference_high'],
          ]),
        );
      }

      b
        ..writeln()
        ..writeln('DAILY NUTRITION (last 30 days)')
        ..writeln(
          row(['log_date', 'total_protein_g', 'calcium_mg', 'fluids_ml']),
        );
      for (final n in results[0] as List) {
        b.writeln(
          row([
            n['log_date'],
            n['total_protein_g'],
            n['calcium_mg'],
            n['fluids_ml'],
          ]),
        );
      }

      b
        ..writeln()
        ..writeln('DAILY SLEEP (last 30 days)')
        ..writeln(
          row([
            'log_date',
            'total_sleep_min',
            'bedtime',
            'wake_time',
            'night_wakes',
          ]),
        );
      for (final s in results[1] as List) {
        b.writeln(
          row([
            s['log_date'],
            s['total_sleep_min'],
            s['bedtime'],
            s['wake_time'],
            s['night_wakes'],
          ]),
        );
      }

      return (b.toString(), null);
    } on PostgrestException catch (e) {
      return (null, e.message);
    }
  }

  // ── Extended-family heights (family_height_records) ─────────────────
  // Grandparent heights for the EXPLORATORY target-height estimate.

  /// All family height records for the active child (record_id,
  /// relation, height_cm). Grandparents are single per relation; aunts/
  /// uncles can be many.
  Future<List<Map<String, dynamic>>> loadFamilyRecords() async {
    final childId = activeChildId;
    if (childId == null) return [];
    try {
      final rows = await sb
          .from('family_height_records')
          .select('record_id, relation, height_cm')
          .eq('child_id', childId);
      return List<Map<String, dynamic>>.from(rows);
    } on PostgrestException {
      return [];
    }
  }

  /// Replace the single stored height for a relation (grandparents).
  Future<String?> setFamilyHeight(String relation, double? heightCm) async {
    final childId = activeChildId;
    if (childId == null) return 'No child selected';
    try {
      await sb
          .from('family_height_records')
          .delete()
          .eq('child_id', childId)
          .eq('relation', relation);
      if (heightCm != null) {
        await sb.from('family_height_records').insert({
          'child_id': childId,
          'relation': relation,
          'height_cm': heightCm,
          'created_by': sb.auth.currentUser?.id,
        });
      }
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Add one record (aunts/uncles — multiple allowed). Returns the new
  /// row, or null on failure.
  Future<Map<String, dynamic>?> addFamilyRecord(
    String relation,
    double heightCm,
  ) async {
    final childId = activeChildId;
    if (childId == null) return null;
    try {
      return await sb
          .from('family_height_records')
          .insert({
            'child_id': childId,
            'relation': relation,
            'height_cm': heightCm,
            'created_by': sb.auth.currentUser?.id,
          })
          .select()
          .single();
    } on PostgrestException {
      return null;
    }
  }

  Future<void> deleteFamilyRecord(dynamic recordId) async {
    try {
      await sb.from('family_height_records').delete().eq('record_id', recordId);
    } on PostgrestException {
      /* non-fatal */
    }
  }

  // ── Unit preference ('metric' | 'imperial'), display-level only ────
  String units = 'metric';

  Future<void> loadUnits() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getString('units');
    if (u != null && u != units) {
      units = u;
      notifyListeners();
    }
  }

  Future<void> setUnits(String u) async {
    units = u;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('units', u);
  }

  // ── Account / settings actions ─────────────────────────────────────

  /// Add a child profile — same shape as the PWA's addChild(), with the
  /// tier limit read live from subscription_tier_limits (client caching
  /// would make the check trivially stale) and a hard product cap of 4.
  Future<String?> addChild({
    required String name,
    required String dob,
    required String sex,
    int? gestationalWeeks,
    double? birthWeightKg,
    double? birthLengthCm,
    bool isSga = false,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return 'Not signed in';
    try {
      final tier = (account?['subscription_tier'] as String?) ?? 'free';
      final limitRow = await sb
          .from('subscription_tier_limits')
          .select('max_children')
          .eq('tier', tier)
          .maybeSingle();
      final tierLimit = (limitRow?['max_children'] as num?)?.toInt();
      final limit = math.min(tierLimit ?? 4, 4);
      final activeCount = children
          .where((c) => c['status'] != 'archived')
          .length;
      if (activeCount >= limit) {
        return 'Your $tier plan supports up to $limit child profiles';
      }

      final payload = <String, dynamic>{
        'parent_id': uid,
        'name': name,
        'date_of_birth': dob,
        'biological_sex': sex,
        'gestational_age_weeks': ?gestationalWeeks,
        'birth_weight_kg': ?birthWeightKg,
        'birth_length_cm': ?birthLengthCm,
        // A confirmed-by-doctor flag the parent relays — the app never
        // computes SGA itself (see migration_sga_tracking.sql).
        if (isSga) 'is_sga': true,
        if (isSga) 'sga_confirmed_by': uid,
      };
      final row = await sb.from('children').insert(payload).select().single();
      children.add(row);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Share a child with a doctor/researcher account by email.
  /// find_clinician_by_email is a SECURITY DEFINER function returning
  /// only user_id + account_role for clinician accounts — it cannot be
  /// used to enumerate emails (parent/unknown emails return no rows).
  Future<String?> shareChildWithClinician(dynamic childId, String email) async {
    try {
      final matches = await sb.rpc(
        'find_clinician_by_email',
        params: {'lookup_email': email},
      );
      final list = List<Map<String, dynamic>>.from(matches as List? ?? []);
      if (list.isEmpty) {
        return 'No Doctor or Researcher account found with that email';
      }
      await sb.from('doctor_patient_assignments').insert({
        'doctor_id': list.first['user_id'],
        'child_id': childId,
        'is_active': true,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505' ? 'Already shared with this account' : e.message;
    }
  }

  Future<List<Map<String, dynamic>>> loadShares(dynamic childId) async {
    try {
      final rows = await sb
          .from('doctor_patient_assignments')
          .select(
            'assignment_id, doctor_id, is_active, user_accounts(email, account_role)',
          )
          .eq('child_id', childId)
          .eq('is_active', true);
      return List<Map<String, dynamic>>.from(rows);
    } on PostgrestException {
      return [];
    }
  }

  Future<String?> revokeShare(dynamic assignmentId) async {
    try {
      await sb
          .from('doctor_patient_assignments')
          .update({'is_active': false})
          .eq('assignment_id', assignmentId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Redeem an activation code via the redeem-code Edge Function.
  /// Returns (successMessage, error) — exactly one is non-null.
  Future<(String?, String?)> redeemActivationCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) return (null, 'Enter an activation code');
    try {
      final res = await sb.functions.invoke(
        'redeem-code',
        body: {'code': code},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['error'] != null) {
        return (null, (data?['error'] ?? 'Redemption failed').toString());
      }
      account?['subscription_tier'] = data['tier'];
      account?['tier_expires_at'] = data['expires_at'];
      account?['billing_source'] = 'code';
      notifyListeners();
      return (
        (data['message'] ?? '${data['tier']} activated!').toString(),
        null,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      return (
        null,
        detail is Map
            ? (detail['error'] ?? e.reasonPhrase ?? 'Redemption failed')
                  .toString()
            : (e.reasonPhrase ?? 'Redemption failed'),
      );
    }
  }

  Future<String?> deleteBoneAge(dynamic id) async {
    // Remove the stored X-ray first (same as the PWA) — non-fatal if
    // it fails, the DB row is the source of truth.
    final rec = boneAgeAssessments.cast<Map<String, dynamic>?>().firstWhere(
      (r) => r?['assessment_id'] == id,
      orElse: () => null,
    );
    final path = rec?['xray_storage_path'] as String?;
    if (path != null) {
      try {
        await sb.storage.from('bone-xrays').remove([path]);
      } catch (_) {}
    }
    return _deleteClinical(
      'bone_age_assessments',
      'assessment_id',
      id,
      boneAgeAssessments,
    );
  }

  /// Upload an X-ray image (already downscaled JPEG bytes) to the
  /// bone-xrays bucket. Returns the storage path, or null on failure.
  Future<String?> uploadBoneXray(Uint8List jpegBytes) async {
    final childId = activeChildId;
    if (childId == null) return null;
    final path = '$childId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await sb.storage
          .from('bone-xrays')
          .uploadBinary(
            path,
            jpegBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  // Signed URLs for X-ray thumbnails, cached per path (valid 1h —
  // plenty for a screen session).
  final Map<String, String> _xrayUrlCache = {};
  Future<String?> xraySignedUrl(String path) async {
    final cached = _xrayUrlCache[path];
    if (cached != null) return cached;
    try {
      final url = await sb.storage
          .from('bone-xrays')
          .createSignedUrl(path, 3600);
      _xrayUrlCache[path] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  /// AI second opinion — sends the stored X-ray to the bone-age-analysis
  /// Edge Function (Claude Vision, GP framework, v2 carpal-anchor
  /// algorithm). The function persists ai_analysis_result on the row;
  /// we mirror it into local state. Returns an error string or null.
  bool boneAgeAiRunning = false;
  Future<String?> runBoneAgeAI(Map<String, dynamic> record) async {
    final path = record['xray_storage_path'] as String?;
    if (path == null) return 'No X-ray image attached';
    boneAgeAiRunning = true;
    notifyListeners();
    try {
      // Download from storage, downscale to <=800px JPEG like the PWA
      // (vision reads bones fine at that size; keeps payload small).
      final bytes = await sb.storage.from('bone-xrays').download(path);
      final resized = await compute(downscaleXrayJpeg, bytes);
      final res = await sb.functions.invoke(
        'bone-age-analysis',
        body: {
          'image_base64': base64Encode(resized),
          'media_type': 'image/jpeg',
          'chronological_age_months': record['chronological_age_months'],
          'sex': activeChildRow?['sex'] ?? 'male',
          'assessment_id': record['assessment_id'],
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['error'] != null) {
        return (data?['error'] ?? 'AI service returned no result').toString();
      }
      final idx = boneAgeAssessments.indexWhere(
        (r) => r['assessment_id'] == record['assessment_id'],
      );
      if (idx >= 0) {
        boneAgeAssessments[idx]['ai_analysis_result'] = data['result'];
        boneAgeAssessments[idx]['ai_analysis_date'] = DateTime.now()
            .toIso8601String();
      }
      return null;
    } on FunctionException catch (e) {
      final detail = e.details;
      return detail is Map
          ? (detail['error'] ?? detail['detail'] ?? e.reasonPhrase).toString()
          : (e.reasonPhrase ?? 'AI analysis failed');
    } catch (e) {
      return e.toString();
    } finally {
      boneAgeAiRunning = false;
      notifyListeners();
    }
  }

  Future<String?> addLabResult({
    required String labDate,
    required String analyteName,
    required double resultValue,
    required String unit,
    double? referenceLow,
    double? referenceHigh,
  }) => _insertClinical('lab_results', {
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
  }) => _insertClinical('illness_events', {
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
  }) => _insertClinical('puberty_events', {
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
          .select(
            'measurement_id, recorded_date, stature_height_cm, mass_weight_kg',
          )
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
    wearableStatus = null;
    _wearableLoadedFor = null;
    weekLogDates = {};
    activeMealSlot = 'breakfast';
    notifyListeners();
  }
}
