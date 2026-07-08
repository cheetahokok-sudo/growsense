import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../growth_math.dart';
import '../i18n.dart';
import '../theme.dart';
import 'medical_modules.dart';

/// Medical tab — growth measurement entry, WHO 2007 height-for-age
/// chart (smooth percentile curves, measured points in measured-blue),
/// and the estimated future trajectory (dashed, estimated-gold) built
/// from the genetic target channel (Zeevi et al. 2024) blended with
/// recent readiness. Colors follow the design system strictly:
/// measured = confirmed data, estimated = forecasts only.
class MedicalScreen extends StatefulWidget {
  const MedicalScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<MedicalScreen> createState() => _MedicalScreenState();
}

class _MedicalScreenState extends State<MedicalScreen> {
  WhoReference? _who;
  WhoBmiReference? _bmi;
  double? _readiness; // 7-day avg readiness for the projection nudge
  String? _readinessChildId;

  @override
  void initState() {
    super.initState();
    loadWhoReference().then((w) {
      if (mounted) setState(() => _who = w);
    });
    loadBmiReference().then((b) {
      if (mounted) setState(() => _bmi = b);
    });
  }

  void _loadReadinessIfNeeded() {
    final child = widget.appState.activeChildRow;
    if (child == null) return;
    final id = child['child_id'] as String;
    if (id == _readinessChildId) return;
    _readinessChildId = id;
    loadWeeklyAnalytics(widget.appState.sb, child).then((a) {
      if (mounted && _readinessChildId == id) {
        setState(() => _readiness = a.avgScore);
      }
    });
  }

  void _pushModule(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final child = widget.appState.activeChildRow;
        if (child == null) {
          return Center(
              child: Text(
                  widget.i18n
                      .t('flutter.no_child_selected', 'No child selected'),
                  style: const TextStyle(color: GsColors.text3)));
        }
        _loadReadinessIfNeeded();
        widget.appState.loadClinicalIfNeeded();
        if (_who == null || _bmi == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final t = widget.i18n.t;
        final s = widget.appState;
        String lastDate(List<Map<String, dynamic>> rows, String col) =>
            rows.isEmpty ? '' : (rows.first[col] as String? ?? '');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ChartCard(
                appState: widget.appState,
                child: child,
                who: _who!,
                bmi: _bmi!,
                readiness: _readiness,
                i18n: widget.i18n),
            const SizedBox(height: 12),
            _TargetHeightCard(child: child, i18n: widget.i18n),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                children: [
                  Text(t('medical.title', 'Clinical log'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: GsColors.measuredLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('5 ${t('flutter.clinical.tools', 'tools')}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GsColors.measuredDark)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                  t('flutter.clinical.explore',
                      'Tap any card to open the pediatric tools — bone age, lab values, puberty staging, and the illness tracker.'),
                  style: const TextStyle(fontSize: 11, color: GsColors.text3)),
            ),
            _ModuleGroup(children: [
              _ModuleRow(
                emoji: '📏',
                title: t('flutter.growth_measurements',
                    'Growth measurements'),
                count: s.measurements.length,
                lastDate:
                    lastDate(s.measurements, 'recorded_date'),
                i18n: widget.i18n,
                onTap: () => _pushModule(MeasurementsScreen(
                    appState: s, i18n: widget.i18n)),
              ),
              _ModuleRow(
                emoji: '🦴',
                title: t('medical.bone_age.title', 'Bone age assessment'),
                count: s.boneAgeAssessments.length,
                lastDate: lastDate(s.boneAgeAssessments, 'study_date'),
                i18n: widget.i18n,
                onTap: () => _pushModule(
                    BoneAgeScreen(appState: s, i18n: widget.i18n)),
              ),
              _ModuleRow(
                emoji: '🧪',
                title: t('medical.lab_values.title', 'Lab values'),
                count: s.labResults.length,
                lastDate: lastDate(s.labResults, 'lab_date'),
                i18n: widget.i18n,
                onTap: () => _pushModule(
                    LabResultsScreen(appState: s, i18n: widget.i18n)),
              ),
              _ModuleRow(
                emoji: '🤒',
                title: t('medical.illness.title',
                    'Development interference log'),
                count: s.illnessEvents.length,
                lastDate: lastDate(s.illnessEvents, 'start_date'),
                i18n: widget.i18n,
                onTap: () => _pushModule(
                    IllnessLogScreen(appState: s, i18n: widget.i18n)),
              ),
              _ModuleRow(
                emoji: '🌱',
                title: t('medical.puberty.title', 'Puberty milestones'),
                count: s.pubertyEvents.length,
                lastDate: lastDate(s.pubertyEvents, 'event_date'),
                i18n: widget.i18n,
                onTap: () => _pushModule(
                    PubertyScreen(appState: s, i18n: widget.i18n)),
                last: true,
              ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                  t('medical.subtitle',
                      'Medical factors that affect growth interpretation'),
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.text3)),
            ),
          ],
        );
      },
    );
  }
}

// ── Clinical module list ────────────────────────────────────────────

class _ModuleGroup extends StatelessWidget {
  const _ModuleGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(children: children),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.emoji,
    required this.title,
    required this.count,
    required this.lastDate,
    required this.i18n,
    required this.onTap,
    this.last = false,
  });
  final String emoji;
  final String title;
  final int count;
  final String lastDate;
  final I18n i18n;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final summary = count == 0
        ? t('flutter.nothing_recorded', 'Nothing recorded yet.')
        : '$count ${t('flutter.records', 'records')} · ${t('flutter.last_record', 'last')} $lastDate';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: GsColors.border)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(summary,
                      style: TextStyle(
                          fontSize: 11,
                          color: count == 0
                              ? GsColors.text3
                              : GsColors.text2)),
                ],
              ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsetsDirectional.only(end: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: GsColors.accentLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GsColors.accentDark)),
              ),
            const Icon(Icons.chevron_right,
                size: 18, color: GsColors.text3),
          ],
        ),
      ),
    );
  }
}

/// Growth measurements module — the entry + history cards that used
/// to sit inline on the Medical tab, now one level deep like the
/// other clinical modules.
class MeasurementsScreen extends StatelessWidget {
  const MeasurementsScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            i18n.t('flutter.growth_measurements', 'Growth measurements'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _EntryCard(appState: appState, i18n: i18n),
            const SizedBox(height: 12),
            _HistoryCard(appState: appState, i18n: i18n),
          ],
        ),
      ),
    );
  }
}

// ── Chart card ──────────────────────────────────────────────────────

class _ChartCard extends StatefulWidget {
  const _ChartCard(
      {required this.appState,
      required this.child,
      required this.who,
      required this.bmi,
      required this.readiness,
      required this.i18n});
  final AppState appState;
  final Map<String, dynamic> child;
  final WhoReference who;
  final WhoBmiReference bmi;
  final double? readiness;
  final I18n i18n;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  String _mode = 'height'; // 'height' | 'bmi'
  bool _showIllness = true;

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final child = widget.child;
    final dob = child['date_of_birth'] as String?;
    final sex = child['biological_sex'] as String?;
    final isBmi = _mode == 'bmi';
    final heightTable = widget.who.tableFor(sex);
    final bmiTable = widget.bmi.tableFor(sex);

    // Measurements oldest → newest as (ageYears, value)
    final meas = <(double, double)>[];
    if (dob != null) {
      for (final m in widget.appState.measurements.reversed) {
        final h = (m['stature_height_cm'] as num?)?.toDouble();
        final wkg = (m['mass_weight_kg'] as num?)?.toDouble();
        final date = m['recorded_date'] as String?;
        if (h == null || date == null) continue;
        if (isBmi) {
          if (wkg == null || h <= 0) continue;
          meas.add((ageYearsAt(dob, date), wkg / ((h / 100) * (h / 100))));
        } else {
          meas.add((ageYearsAt(dob, date), h));
        }
      }
    }

    // Illness period spans (start→end age), only when toggled on.
    final spans = <(double, double)>[];
    if (_showIllness && dob != null) {
      final todayIso = todayISO();
      for (final e in widget.appState.illnessEvents) {
        final s = e['start_date'] as String?;
        if (s == null) continue;
        final end = (e['end_date'] as String?) ?? todayIso;
        spans.add((ageYearsAt(dob, s), ageYearsAt(dob, end)));
      }
    }

    List<double> bandsForAge(double ageMonths) {
      if (isBmi) {
        final lms = interpolateLms(bmiTable, ageMonths);
        return [
          for (final z in [-2.0, -1.0, 0.0, 1.0, 2.0])
            bmiAtZ(z, lms.l, lms.m, lms.s)
        ];
      }
      return interpolateBands(heightTable, ageMonths);
    }

    // Readout for the latest measurement + (height only) projection.
    String readout = t('flutter.no_measurements_hint',
        'No measurements yet — add one below.');
    List<ProjectionPoint> projection = [];
    if (meas.isNotEmpty) {
      final (age, v) = meas.last;
      if (isBmi) {
        final lms = interpolateLms(bmiTable, age * 12);
        final z = bmiToZ(v, lms.l, lms.m, lms.s);
        final cls = bmiClassification(z);
        readout =
            'BMI ${v.toStringAsFixed(1)} · ${age.toStringAsFixed(1)}y · P${zToPercentile(z).round()} · ${t('flutter.bmi.$cls', cls)}';
      } else {
        final bands = interpolateBands(heightTable, age * 12);
        final z = zFromHeight(bands, v);
        readout =
            '${v.toStringAsFixed(1)} cm · ${age.toStringAsFixed(1)}y · P${zToPercentile(z).round()} ${t('flutter.percentile', 'percentile')} (z ${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)})';
        final target = calculateTargetHeight(
          motherHeightCm: (child['mother_height_cm'] as num?)?.toDouble(),
          fatherHeightCm: (child['father_height_cm'] as num?)?.toDouble(),
          motherAge: (child['mother_current_age'] as num?)?.toInt(),
          fatherAge: (child['father_current_age'] as num?)?.toInt(),
          childSex: sex,
        );
        projection = projectGrowth(
          table: heightTable,
          currentAgeYears: age,
          currentHeightCm: v,
          targetZ: target?.correctedZ,
          readinessScore: widget.readiness,
        );
      }
    }

    final title = isBmi
        ? '${t('analytics.charts.bmi_for_age', 'BMI-for-age')} · WHO 2007'
        : '${t('analytics.charts.height_for_age', 'Height-for-age')} · WHO 2007';

    return Container(
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode toggle (Height | BMI)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: GsColors.surface2,
              borderRadius: BorderRadius.circular(GsRadius.sm + 2),
            ),
            child: Row(
              children: [
                for (final m in ['height', 'bmi'])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _mode = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _mode == m
                              ? GsColors.surface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(GsRadius.sm),
                          boxShadow: _mode == m ? gsShadow : null,
                        ),
                        child: Text(
                            m == 'bmi'
                                ? t('flutter.chart.bmi_mode', 'BMI')
                                : t('flutter.chart.height_mode', 'Height'),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: _mode == m
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _mode == m
                                    ? GsColors.text
                                    : GsColors.text2)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color:
                            isBmi ? GsColors.accent : GsColors.measured)),
              ),
              // Illness-period show/hide toggle
              GestureDetector(
                onTap: () => setState(() => _showIllness = !_showIllness),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _showIllness
                            ? GsColors.flag.withValues(alpha: 0.25)
                            : GsColors.surface2,
                        border: Border.all(
                            color: _showIllness
                                ? GsColors.flag
                                : GsColors.border2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: _showIllness
                          ? const Icon(Icons.check,
                              size: 10, color: GsColors.flag)
                          : null,
                    ),
                    const SizedBox(width: 5),
                    Text(t('flutter.chart.show_illness', 'Illness periods'),
                        style: const TextStyle(
                            fontSize: 10.5, color: GsColors.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(readout,
              style: const TextStyle(fontSize: 11.5, color: GsColors.text2)),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            width: double.infinity,
            child: CustomPaint(
              painter: _GrowthChartPainter(
                bandsForAge: bandsForAge,
                ageMinYears: (isBmi ? bmiTable : heightTable).first[0] / 12,
                ageMaxYears: (isBmi ? bmiTable : heightTable).last[0] / 12,
                measurements: meas,
                projection: projection,
                emptyLabel: t('flutter.no_measurements_chart',
                    'No measurements logged yet'),
                yStep: isBmi ? 2 : 10,
                bandLabels: isBmi
                    ? const ['−2', '−1', '0', '+1', '+2']
                    : const ['3', '15', '50', '85', '97'],
                illnessSpans: spans,
                bmiZones: isBmi,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isBmi ? t('flutter.chart.bmi_caption') : t('flutter.chart_caption'),
            style: const TextStyle(fontSize: 10, color: GsColors.text3),
          ),
        ],
      ),
    );
  }
}

/// Smooth WHO growth chart. Percentile curves are drawn as Catmull-Rom
/// cubic splines through the (6-monthly) WHO rows, so they render as
/// the smooth physiologic curves parents see in a paediatrician's
/// chart, not straight segments.
class _GrowthChartPainter extends CustomPainter {
  _GrowthChartPainter({
    required this.bandsForAge,
    required this.ageMinYears,
    required this.ageMaxYears,
    required this.measurements,
    required this.projection,
    required this.emptyLabel,
    required this.yStep,
    required this.bandLabels,
    this.illnessSpans = const [],
    this.bmiZones = false,
  });
  final List<double> Function(double ageMonths) bandsForAge;
  final double ageMinYears, ageMaxYears;
  final List<(double, double)> measurements; // (ageYears, value) asc
  final List<ProjectionPoint> projection;
  final String emptyLabel;
  final int yStep;
  final List<String> bandLabels; // right-edge labels, low→high
  final List<(double, double)> illnessSpans; // (startAge, endAge)
  final bool bmiZones; // color the channels as BMI health zones

  static const _padL = 34.0, _padR = 8.0, _padT = 8.0, _padB = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    // X range: around the data if present, else the reference window
    double minAge = ageMinYears, maxAge = ageMaxYears;
    if (measurements.isNotEmpty) {
      final firstAge = measurements.first.$1;
      final lastAge = measurements.last.$1;
      final projEnd = projection.isEmpty ? lastAge + 2.0 : lastAge + 3.0;
      minAge = math.max(ageMinYears, firstAge - 0.75);
      maxAge = math.min(ageMaxYears, math.max(projEnd, lastAge + 2.0));
    }
    final w = size.width - _padL - _padR;
    final h = size.height - _padT - _padB;

    // Only what falls inside the visible age window participates in
    // drawing and y-scaling — a child measured since birth would
    // otherwise drag the y-axis down to infant heights and paint
    // lines beyond the plot edges.
    final visMeas = [
      for (final m in measurements)
        if (m.$1 >= minAge - 1e-9 && m.$1 <= maxAge + 1e-9) m,
    ];
    final visProj = [
      for (final p in projection)
        if (p.ageYears >= minAge - 1e-9 && p.ageYears <= maxAge + 1e-9) p,
    ];

    // Sample bands across the visible range
    const samples = 40;
    final bandPts = <List<Offset>>[[], [], [], [], []]; // p3..p97 in y-units
    final bandVals = <List<double>>[];
    for (var i = 0; i <= samples; i++) {
      final age = minAge + (maxAge - minAge) * i / samples;
      bandVals.add(bandsForAge(age * 12));
    }
    var yMinV = double.infinity, yMaxV = -double.infinity;
    for (final b in bandVals) {
      yMinV = math.min(yMinV, b[0]);
      yMaxV = math.max(yMaxV, b[4]);
    }
    // Include visible measured + projected values in the y-range
    for (final (_, cm) in visMeas) {
      yMinV = math.min(yMinV, cm);
      yMaxV = math.max(yMaxV, cm);
    }
    for (final p in visProj) {
      yMinV = math.min(yMinV, p.heightCm);
      yMaxV = math.max(yMaxV, p.heightCm);
    }
    yMinV -= 3;
    yMaxV += 3;

    double px(double age) => _padL + (age - minAge) / (maxAge - minAge) * w;
    double py(double cm) => _padT + h - (cm - yMinV) / (yMaxV - yMinV) * h;

    for (var i = 0; i <= samples; i++) {
      final age = minAge + (maxAge - minAge) * i / samples;
      for (var b = 0; b < 5; b++) {
        bandPts[b].add(Offset(px(age), py(bandVals[i][b])));
      }
    }

    // ── Grid ──
    final gridPaint = Paint()
      ..color = GsColors.border
      ..strokeWidth = 0.7;
    final labelStyle = const TextStyle(fontSize: 9, color: GsColors.text3);
    for (var v = (yMinV / yStep).ceil() * yStep; v < yMaxV; v += yStep) {
      final y = py(v.toDouble());
      canvas.drawLine(Offset(_padL, y), Offset(_padL + w, y), gridPaint);
      _text(canvas, '$v', Offset(2, y - 6), labelStyle);
    }
    for (var age = minAge.ceil(); age <= maxAge.floor(); age++) {
      final x = px(age.toDouble());
      canvas.drawLine(
          Offset(x, _padT), Offset(x, _padT + h), gridPaint);
      _text(canvas, '${age}y', Offset(x - 8, _padT + h + 6), labelStyle);
    }

    // Everything data-shaped stays inside the plot rectangle.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(_padL, _padT, w, h));

    // ── Illness period shading (behind the curves) ──
    final illnessPaint = Paint()..color = GsColors.flag.withValues(alpha: 0.10);
    for (final (startA, endA) in illnessSpans) {
      final x0 = px(startA.clamp(minAge, maxAge));
      final x1 = px((endA <= startA ? startA + 0.02 : endA).clamp(minAge, maxAge));
      canvas.drawRect(
          Rect.fromLTRB(x0, _padT, math.max(x1, x0 + 1.5), _padT + h),
          illnessPaint);
    }

    // ── Percentile / BMI channels (smooth) ──
    void fillBetween(List<Offset> top, List<Offset> bottom, Color color) {
      final path = _smoothPath(bottom)
        ..lineTo(top.last.dx, top.last.dy);
      final topRev = top.reversed.toList();
      final topPath = _smoothPath(topRev);
      path.extendWithPath(topPath, Offset.zero);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    if (bmiZones) {
      // BMI health zones: bands are [-2, -1, 0, +1, +2] SD.
      final botEdge = [for (final p in bandPts[4]) Offset(p.dx, _padT + h)];
      final topEdge = [for (final p in bandPts[0]) Offset(p.dx, _padT)];
      // thinness (< −2 SD) down to the bottom edge
      fillBetween(bandPts[0], botEdge, GsColors.measured.withValues(alpha: 0.10));
      // healthy channel (−2 to +1 SD)
      fillBetween(bandPts[3], bandPts[0], GsColors.accent.withValues(alpha: 0.10));
      // overweight (+1 to +2 SD)
      fillBetween(bandPts[4], bandPts[3], GsColors.estimated.withValues(alpha: 0.16));
      // obesity (> +2 SD) up to the top edge
      fillBetween(topEdge, bandPts[4], GsColors.flag.withValues(alpha: 0.12));
    } else {
      fillBetween(
          bandPts[4], bandPts[0], GsColors.text3.withValues(alpha: 0.12));
      fillBetween(
          bandPts[3], bandPts[1], GsColors.text3.withValues(alpha: 0.14));
    }

    void curve(List<Offset> pts, Color color, double width) {
      canvas.drawPath(
          _smoothPath(pts),
          Paint()
            ..color = color
            ..strokeWidth = width
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }

    curve(bandPts[0], GsColors.text3.withValues(alpha: 0.5), 1.0);
    curve(bandPts[1], GsColors.text3.withValues(alpha: 0.6), 1.1);
    curve(bandPts[2], GsColors.text2.withValues(alpha: 0.8), 1.5);
    curve(bandPts[3], GsColors.text3.withValues(alpha: 0.6), 1.1);
    curve(bandPts[4], GsColors.text3.withValues(alpha: 0.5), 1.0);

    // ── Projection (dashed, estimated gold) ──
    if (visProj.length >= 2) {
      final projPts = [
        for (final p in visProj) Offset(px(p.ageYears), py(p.heightCm)),
      ];
      final dashed = _dashPath(_smoothPath(projPts), 6, 4);
      canvas.drawPath(
          dashed,
          Paint()
            ..color = GsColors.estimated
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
      canvas.drawCircle(projPts.last, 3.5, Paint()..color = GsColors.estimated);
    }

    // ── Measured line + points ──
    if (visMeas.isNotEmpty) {
      final pts = [
        for (final (age, cm) in visMeas) Offset(px(age), py(cm)),
      ];
      if (pts.length >= 2) {
        canvas.drawPath(
            _smoothPath(pts),
            Paint()
              ..color = GsColors.measured
              ..strokeWidth = 2.6
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round);
      }
      for (var i = 0; i < pts.length; i++) {
        final isLatest = i == pts.length - 1;
        canvas.drawCircle(
            pts[i], isLatest ? 5 : 4, Paint()..color = GsColors.measured);
        canvas.drawCircle(
            pts[i], isLatest ? 2.5 : 2, Paint()..color = Colors.white);
      }
    }

    canvas.restore();

    // Band edge labels on the right, outside the clip so they can sit
    // in the right padding gutter.
    for (var b = 0; b < 5 && b < bandLabels.length; b++) {
      _text(canvas, bandLabels[b],
          Offset(bandPts[b].last.dx - 14, bandPts[b].last.dy - 11),
          const TextStyle(fontSize: 8, color: GsColors.text3));
    }

    if (visMeas.isEmpty) {
      _text(
          canvas,
          emptyLabel,
          Offset(_padL + w / 2 - 70, _padT + h / 2 - 6),
          const TextStyle(fontSize: 11, color: GsColors.text3));
    }
  }

  /// Catmull-Rom spline through the points, emitted as cubic Béziers —
  /// this is what makes the WHO curves render smoothly.
  static Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 1) return path;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[0] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  static Path _dashPath(Path source, double dashLen, double gapLen) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = math.min(dist + dashLen, metric.length);
        out.addPath(metric.extractPath(dist, end), Offset.zero);
        dist = end + gapLen;
      }
    }
    return out;
  }

  static void _text(
      Canvas canvas, String s, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _GrowthChartPainter old) =>
      old.measurements != measurements ||
      old.projection != projection ||
      old.illnessSpans != illnessSpans ||
      old.bmiZones != bmiZones;
}

// ── Target height card ──────────────────────────────────────────────

class _TargetHeightCard extends StatelessWidget {
  const _TargetHeightCard({required this.child, required this.i18n});
  final Map<String, dynamic> child;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final target = calculateTargetHeight(
      motherHeightCm: (child['mother_height_cm'] as num?)?.toDouble(),
      fatherHeightCm: (child['father_height_cm'] as num?)?.toDouble(),
      motherAge: (child['mother_current_age'] as num?)?.toInt(),
      fatherAge: (child['father_current_age'] as num?)?.toInt(),
      childSex: child['biological_sex'] as String?,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.estimatedLight,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.estimated.withValues(alpha: 0.4)),
      ),
      child: target == null
          ? Text(t('flutter.add_parent_heights'),
              style: const TextStyle(
                  fontSize: 12, color: GsColors.estimatedDark))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    t('flutter.genetic_target_title',
                        'Genetic target height (adult)'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GsColors.estimatedDark)),
                const SizedBox(height: 6),
                Text(
                    '${target.targetHeightCm.toStringAsFixed(1)} cm '
                    '(${t('flutter.range', 'range')} ${target.rangeLowCm.toStringAsFixed(1)}–${target.rangeHighCm.toStringAsFixed(1)})',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: GsColors.estimatedDark)),
                const SizedBox(height: 4),
                Text(
                    '${t('flutter.target_method')} ${target.tannerMidParentalCm.toStringAsFixed(1)} cm.',
                    style: const TextStyle(
                        fontSize: 10.5, color: GsColors.estimatedDark)),
              ],
            ),
    );
  }
}

// ── Measurement entry ───────────────────────────────────────────────

class _EntryCard extends StatefulWidget {
  const _EntryCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  final _height = TextEditingController();
  final _weight = TextEditingController();
  String _date = todayISO();
  bool _busy = false;

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    if (h == null || w == null || h <= 0 || w <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: GsColors.flag,
          content: Text(t('flutter.invalid_height_weight',
              'Enter a valid height and weight'))));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState
        .addMeasurement(date: _date, heightCm: h, weightKg: w);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(err == null
            ? '✅ ${t('flutter.measurement_logged', 'Measurement logged')}'
            : '${t('flutter.not_saved', 'Not saved')}: $err')));
    if (err == null) {
      _height.clear();
      _weight.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              widget.i18n
                  .t('analytics.log_measurement.title', 'Log measurement'),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accent)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: GsColors.border2),
                    foregroundColor: GsColors.text,
                  ),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(_date, style: const TextStyle(fontSize: 12.5)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(_date),
                      firstDate: now.subtract(const Duration(days: 365 * 19)),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setState(() => _date = localISO(picked));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          widget.i18n.t('common.height_cm', 'Height (cm)'),
                      isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          widget.i18n.t('common.weight_kg', 'Weight (kg)'),
                      isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy
                ? widget.i18n.t('flutter.saving', 'Saving…')
                : widget.i18n
                    .t('flutter.save_measurement', 'Save measurement')),
          ),
        ],
      ),
    );
  }
}

// ── History list ────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final items = appState.measurements;
    return Container(
      padding: const EdgeInsets.all(14),
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
              Text(t('flutter.measurement_history', 'Measurement history'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GsColors.measured)),
              Text('${items.length} ${t('flutter.records', 'records')}',
                  style:
                      const TextStyle(fontSize: 11, color: GsColors.text3)),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(t('flutter.nothing_recorded', 'Nothing recorded yet.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: GsColors.text3)),
            )
          else
            for (final m in items)
              Row(
                children: [
                  Expanded(
                    child: Text(m['recorded_date'] as String? ?? '',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                  Text(
                    '${(m['stature_height_cm'] as num?)?.toStringAsFixed(1)} cm · '
                    '${(m['mass_weight_kg'] as num?)?.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: GsColors.text2,
                        fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close,
                        size: 16, color: GsColors.text3),
                    onPressed: () async {
                      final err = await appState
                          .deleteMeasurement(m['measurement_id']);
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: GsColors.flag,
                            content: Text(
                                '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                      }
                    },
                  ),
                ],
              ),
        ],
      ),
    );
  }
}
