// ══════════════════════════════════════════════════════════════════
// Today-tab HUD widgets — port of the PWA's Growth Readiness HUD,
// logging-consistency row, and sleep editor. Scoring is updateHUD()
// verbatim:
//   nutrition = protein/boost·30% + calcium/1300·50% + water/8·20%
//   activity  = Σ(duration × tier weight) / 60 min, capped
//   sleep     = duration/9.5h·35% + bedtime≤21:30·40% + wakes·25%
//   overall   = nutrition·30 + activity·30 + sleep·40
// Ring colors follow the design system: nutrition accent, activity
// measured, sleep estimated.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

class HudScores {
  final double nutPct, actPct, slpPct; // 0..1
  final double pR, cR, wR; // nutrition components, 0..1
  final int score; // 0..100
  final int proteinBoostTarget;
  HudScores(this.nutPct, this.actPct, this.slpPct, this.pR, this.cR, this.wR,
      this.score, this.proteinBoostTarget);
}

HudScores computeHudScores(AppState appState) {
  final child = appState.activeChildRow;
  final latestWeight = appState.measurements.isEmpty
      ? null
      : (appState.measurements.first['mass_weight_kg'] as num?)?.toDouble();
  final boost = calcProteinBoostTargetG(
    child?['date_of_birth'] as String?,
    latestWeight,
    child?['biological_sex'] as String?,
  );

  double itemsSum(String col) => appState.nutritionLogItems.fold<double>(
      0, (sum, i) => sum + ((i[col] as num?)?.toDouble() ?? 0));
  final saved = appState.nutrition;
  double savedNum(String col) => (saved?[col] as num?)?.toDouble() ?? 0;

  // Live item sums win over the last save, matching how the PWA's
  // in-memory day state runs ahead of the daily_nutrition row.
  final protein = math.max(
      itemsSum('protein_g'),
      savedNum('protein_breakfast_g') +
          savedNum('protein_lunch_g') +
          savedNum('protein_dinner_g'));
  final calcium = math.max(itemsSum('calcium_mg'), savedNum('calcium_mg'));
  final waterGlasses = savedNum('fluids_ml') / 250;

  final pR = (protein / boost).clamp(0.0, 1.0);
  final cR = (calcium / 1300).clamp(0.0, 1.0);
  final wR = (waterGlasses / 8).clamp(0.0, 1.0);
  final nutPct = pR * 0.30 + cR * 0.50 + wR * 0.20;

  double weightedMin = 0;
  for (final item in appState.activityItems) {
    const weights = {
      'high_impact': 1.0,
      'weight_bearing': 0.65,
      'cardio': 0.35,
      'flexibility': 0.15,
      'lifestyle': 0.15,
    };
    weightedMin += ((item['duration_min'] as num?)?.toDouble() ?? 0) *
        (weights[item['tier']] ?? 0.15);
  }
  final actPct = (weightedMin / 60).clamp(0.0, 1.0);

  double slpPct = 0;
  final sleep = appState.sleep;
  if (sleep != null) {
    final totalMin = (sleep['total_sleep_min'] as num?)?.toDouble() ?? 0;
    final durR = (totalMin / (9.5 * 60)).clamp(0.0, 1.0);
    double onTimeR = 0;
    final bedtime = sleep['bedtime'] as String?;
    if (bedtime != null && bedtime.contains(':')) {
      final parts = bedtime.split(':');
      final bedM = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      const cutoff = 21 * 60 + 30;
      onTimeR =
          bedM <= cutoff ? 1.0 : math.max(0, 1 - (bedM - cutoff) / 120);
    }
    final wakes = (sleep['night_wakes'] as num?)?.toInt() ?? 0;
    final wakeR = math.max(0.0, 1 - wakes * 0.25);
    slpPct = durR * 0.35 + onTimeR * 0.4 + wakeR * 0.25;
  }

  final score = (nutPct * 30 + actPct * 30 + slpPct * 40).round();
  return HudScores(nutPct, actPct, slpPct, pR, cR, wR, score, boost);
}

// ── Readiness card ──────────────────────────────────────────────────

class ReadinessCard extends StatelessWidget {
  const ReadinessCard({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final s = computeHudScores(appState);
    return Container(
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: GsColors.accent,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(GsRadius.md)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('today.hud.title', 'Readiness reading'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: GsColors.accent)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ReadinessRing(
                        nut: s.nutPct,
                        act: s.actPct,
                        slp: s.slpPct,
                        score: s.score,
                        i18n: i18n),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [
                          _MetricRow(
                              color: GsColors.accent,
                              name: t('common.nutrition', 'Nutrition'),
                              pct: s.nutPct),
                          const SizedBox(height: 10),
                          _MetricRow(
                              color: GsColors.measured,
                              name: t('common.activity', 'Activity'),
                              pct: s.actPct),
                          const SizedBox(height: 10),
                          _MetricRow(
                              color: GsColors.estimated,
                              name: t('common.sleep', 'Sleep'),
                              pct: s.slpPct),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MiniBar(
                        label: t('common.protein', 'Protein'),
                        pct: s.pR,
                        color: GsColors.accent),
                    _MiniBar(
                        label: t('common.calcium', 'Calcium'),
                        pct: s.cR,
                        color: GsColors.accent),
                    _MiniBar(
                        label: t('common.water', 'Water'),
                        pct: s.wR,
                        color: GsColors.measured),
                    _MiniBar(
                        label: t('common.exercise', 'Exercise'),
                        pct: s.actPct,
                        color: GsColors.measured),
                    _MiniBar(
                        label: t('common.sleep', 'Sleep'),
                        pct: s.slpPct,
                        color: GsColors.estimated,
                        last: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    '${t('flutter.protein_target', 'Growth target')}: ${s.proteinBoostTarget} g',
                    style:
                        const TextStyle(fontSize: 10, color: GsColors.text3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated readiness ring — three concentric gradient arcs with a
/// soft glow and end-cap dots, and a score that counts up. Re-animates
/// whenever the component scores change (keyed on their values).
class _ReadinessRing extends StatelessWidget {
  const _ReadinessRing(
      {required this.nut,
      required this.act,
      required this.slp,
      required this.score,
      required this.i18n});
  final double nut, act, slp;
  final int score;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$nut-$act-$slp'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, a, _) {
        return SizedBox(
          width: 122,
          height: 122,
          child: CustomPaint(
            painter: _RingsPainter(nut: nut, act: act, slp: slp, anim: a),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      colors: [GsColors.accent, GsColors.measured],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(r),
                    child: Text('${(score * a).round()}',
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -1,
                            color: Colors.white)),
                  ),
                  Text(i18n.t('today.hud.score_suffix', 'of 100'),
                      style: const TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.5,
                          color: GsColors.text3)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Three concentric progress rings with gradient sweep, soft glow, and
/// a bright end-cap dot for a premium finish.
class _RingsPainter extends CustomPainter {
  _RingsPainter(
      {required this.nut,
      required this.act,
      required this.slp,
      required this.anim});
  final double nut, act, slp, anim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 122;
    final stroke = 8.0 * scale;

    void ring(double radius, double rawPct, Color light, Color full) {
      final r = radius * scale;
      final rect = Rect.fromCircle(center: center, radius: r);
      final pct = (rawPct.clamp(0.0, 1.0)) * anim;

      // Track
      canvas.drawCircle(
          center,
          r,
          Paint()
            ..color = GsColors.surface2
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke);
      if (pct <= 0.001) return;

      const start = -math.pi / 2;
      final sweep = 2 * math.pi * pct;

      // Soft glow underneath
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = full.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke + 4 * scale
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale));

      // Gradient arc
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [light, full],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);

      // Bright end-cap dot
      final end = start + sweep;
      final tip = center + Offset(math.cos(end) * r, math.sin(end) * r);
      canvas.drawCircle(tip, stroke * 0.62, Paint()..color = full);
      canvas.drawCircle(tip, stroke * 0.26, Paint()..color = Colors.white);
    }

    ring(48, nut, const Color(0xFF5FA87E), GsColors.accent);
    ring(37, act, const Color(0xFF5B8FC0), GsColors.measured);
    ring(26, slp, const Color(0xFFC9A45E), GsColors.estimated);
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.nut != nut ||
      old.act != act ||
      old.slp != slp ||
      old.anim != anim;
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(
      {required this.color, required this.name, required this.pct});
  final Color color;
  final String name;
  final double pct;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(name,
              style: const TextStyle(fontSize: 12.5, color: GsColors.text2)),
        ),
        Text('${(pct * 100).round()}%',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar(
      {required this.label,
      required this.pct,
      required this.color,
      this.last = false});
  final String label;
  final double pct;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: last ? 0 : 8),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Stack(
                  children: [
                    Container(color: GsColors.surface2),
                    FractionallySizedBox(
                      widthFactor: pct.clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 9, color: GsColors.text3)),
          ],
        ),
      ),
    );
  }
}

// ── Logging consistency ─────────────────────────────────────────────

class ConsistencyCard extends StatelessWidget {
  const ConsistencyCard(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: (now.weekday - 1) % 7));
    final today = todayISO();
    final letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final logged = <bool>[];
    final dates = <String>[];
    for (var i = 0; i < 7; i++) {
      final d = localISO(monday.add(Duration(days: i)));
      dates.add(d);
      logged.add(appState.weekLogDates.contains(d));
    }
    final count = logged.where((v) => v).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                    t('today.streak.title', 'Logging consistency, this week'),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: GsColors.accentLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count / 7 ${t('flutter.days', 'days')}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: GsColors.accentDark)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: logged[i] ? GsColors.accent : GsColors.surface2,
                    shape: BoxShape.circle,
                    border: dates[i] == today
                        ? Border.all(color: GsColors.accentDark, width: 2)
                        : null,
                  ),
                  child: Text(letters[i],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: logged[i] ? Colors.white : GsColors.text3)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sleep editor ────────────────────────────────────────────────────

class SleepEditorCard extends StatefulWidget {
  const SleepEditorCard(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<SleepEditorCard> createState() => _SleepEditorCardState();
}

class _SleepEditorCardState extends State<SleepEditorCard> {
  TimeOfDay? _bed;
  TimeOfDay? _wake;
  int? _wakes;
  bool _busy = false;
  String? _seededFor; // childId+logDate the fields were last seeded from

  static TimeOfDay? _parse(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _seedFromState() {
    final key = '${widget.appState.activeChildId}|${widget.appState.logDate}';
    if (_seededFor == key) return;
    _seededFor = key;
    final sleep = widget.appState.sleep;
    _bed = _parse(sleep?['bedtime'] as String?) ??
        const TimeOfDay(hour: 21, minute: 0);
    _wake = _parse(sleep?['wake_time'] as String?) ??
        const TimeOfDay(hour: 6, minute: 30);
    _wakes = (sleep?['night_wakes'] as num?)?.toInt() ?? 0;
  }

  int get _totalMin {
    final bedM = _bed!.hour * 60 + _bed!.minute;
    var wakeM = _wake!.hour * 60 + _wake!.minute;
    if (bedM > wakeM) wakeM += 1440;
    return wakeM - bedM;
  }

  Future<void> _pick(bool isBed) async {
    final picked = await showTimePicker(
        context: context, initialTime: isBed ? _bed! : _wake!);
    if (picked != null) {
      setState(() => isBed ? _bed = picked : _wake = picked);
    }
  }

  Future<void> _syncWearable() async {
    final t = widget.i18n.t;
    final (nights, err) = await widget.appState.syncFitbit();
    if (!mounted) return;
    _seededFor = null; // re-seed from freshly synced values
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
      content: Text(err == null
          ? '✅ ${nights ?? 0} ${t('flutter.dev.nights_synced', 'nights synced')}'
          : '${t('flutter.not_saved', 'Sync failed')}: $err'),
    ));
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    setState(() => _busy = true);
    final err = await widget.appState.saveSleep(
      bedtime: _fmt(_bed!),
      wakeTime: _fmt(_wake!),
      nightWakes: _wakes!,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(err == null
            ? '✅ ${t('flutter.sleep_saved', 'Sleep saved')}'
            : '${t('flutter.not_saved', 'Not saved')}: $err')));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        _seedFromState();
        final total = _totalMin;
        return Container(
          decoration: BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.circular(GsRadius.md),
            border: Border.all(color: GsColors.border),
            boxShadow: gsShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  color: GsColors.estimated,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(GsRadius.md)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(t('common.sleep', 'Sleep'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: GsColors.estimated)),
                        ),
                        Text('${total ~/ 60}h ${total % 60}m',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: GsColors.estimatedDark)),
                      ],
                    ),
                    _WearableSyncRow(
                        appState: widget.appState,
                        i18n: widget.i18n,
                        onSync: widget.appState.syncingWearable
                            ? null
                            : _syncWearable),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TimeField(
                            label: t('today.sleep.bedtime', 'Bedtime'),
                            sub: t('today.sleep.bedtime_sub',
                                'Target: before 21:30'),
                            value: _fmt(_bed!),
                            onTap: () => _pick(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TimeField(
                            label: t('today.sleep.wake_time', 'Wake time'),
                            sub: t('today.sleep.wake_sub', 'Morning arousal'),
                            value: _fmt(_wake!),
                            onTap: () => _pick(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                              t('flutter.night_wakes', 'Night wakes'),
                              style: const TextStyle(
                                  fontSize: 12.5, color: GsColors.text2)),
                        ),
                        Row(
                          children: [
                            _StepBtn(
                                icon: Icons.remove,
                                onTap: _wakes! > 0
                                    ? () => setState(() => _wakes = _wakes! - 1)
                                    : null),
                            SizedBox(
                              width: 34,
                              child: Text('$_wakes',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                            _StepBtn(
                                icon: Icons.add,
                                onTap: _wakes! < 9
                                    ? () => setState(() => _wakes = _wakes! + 1)
                                    : null),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : _save,
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      child: Text(_busy
                          ? t('flutter.saving', 'Saving…')
                          : t('flutter.save_sleep', 'Save sleep')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sleep-card wearable strip: when a device is connected, shows the
/// synced account + a Sync now button; otherwise surfaces the child's
/// saved wearable email as a cross-check hint. Both come straight from
/// the shared wearable status the Devices screen uses.
class _WearableSyncRow extends StatelessWidget {
  const _WearableSyncRow(
      {required this.appState, required this.i18n, required this.onSync});
  final AppState appState;
  final I18n i18n;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final status = appState.wearableStatus;
    final childEmail =
        (appState.activeChildRow?['wearable_account_email'] as String?)
            ?.trim();

    if (status != null) {
      final email = status['google_email'] as String? ?? '';
      final lastSync = (status['last_sync_at'] as String?)?.split('T').first;
      final mismatch = childEmail != null &&
          childEmail.isNotEmpty &&
          childEmail.toLowerCase() != email.toLowerCase();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: GsColors.estimatedLight,
            borderRadius: BorderRadius.circular(GsRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.watch_outlined,
                      size: 15, color: GsColors.estimatedDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${t('flutter.sleep.synced_from', 'Synced from')} $email${lastSync != null ? ' · $lastSync' : ''}',
                        style: const TextStyle(
                            fontSize: 10.5, color: GsColors.estimatedDark),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onSync,
                    child: Text(
                        onSync == null
                            ? t('flutter.saving', 'Syncing…')
                            : t('flutter.dev.sync_now', 'Sync now'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: onSync == null
                                ? GsColors.text3
                                : GsColors.accent)),
                  ),
                ],
              ),
              if (mismatch)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '⚠️ ${t('flutter.sleep.mismatch', 'Connected account differs from this child\'s saved wearable email')}',
                      style: const TextStyle(
                          fontSize: 9.5, color: GsColors.flagDark)),
                ),
            ],
          ),
        ),
      );
    }

    if (childEmail != null && childEmail.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            const Icon(Icons.watch_outlined,
                size: 14, color: GsColors.text3),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  '$childEmail · ${t('flutter.sleep.connect_devices', 'connect in Devices to auto-sync')}',
                  style: const TextStyle(fontSize: 10, color: GsColors.text3),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField(
      {required this.label,
      required this.sub,
      required this.value,
      required this.onTap});
  final String label;
  final String sub;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(GsRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: GsColors.text2)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 9, color: GsColors.text3)),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? GsColors.surface2 : GsColors.accentLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap == null ? GsColors.text3 : GsColors.accentDark),
      ),
    );
  }
}
