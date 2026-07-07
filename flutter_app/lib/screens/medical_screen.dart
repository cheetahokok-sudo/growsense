import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../growth_math.dart';
import '../theme.dart';

/// Medical tab — growth measurement entry, WHO 2007 height-for-age
/// chart (smooth percentile curves, measured points in measured-blue),
/// and the estimated future trajectory (dashed, estimated-gold) built
/// from the genetic target channel (Zeevi et al. 2024) blended with
/// recent readiness. Colors follow the design system strictly:
/// measured = confirmed data, estimated = forecasts only.
class MedicalScreen extends StatefulWidget {
  const MedicalScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<MedicalScreen> createState() => _MedicalScreenState();
}

class _MedicalScreenState extends State<MedicalScreen> {
  WhoReference? _who;
  double? _readiness; // 7-day avg readiness for the projection nudge
  String? _readinessChildId;

  @override
  void initState() {
    super.initState();
    loadWhoReference().then((w) {
      if (mounted) setState(() => _who = w);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final child = widget.appState.activeChildRow;
        if (child == null) {
          return const Center(
              child: Text('No child selected',
                  style: TextStyle(color: GsColors.text3)));
        }
        _loadReadinessIfNeeded();
        if (_who == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ChartCard(
                appState: widget.appState,
                child: child,
                who: _who!,
                readiness: _readiness),
            const SizedBox(height: 12),
            _TargetHeightCard(child: child),
            const SizedBox(height: 12),
            _EntryCard(appState: widget.appState),
            const SizedBox(height: 12),
            _HistoryCard(appState: widget.appState),
          ],
        );
      },
    );
  }
}

// ── Chart card ──────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard(
      {required this.appState,
      required this.child,
      required this.who,
      required this.readiness});
  final AppState appState;
  final Map<String, dynamic> child;
  final WhoReference who;
  final double? readiness;

  @override
  Widget build(BuildContext context) {
    final dob = child['date_of_birth'] as String?;
    final sex = child['biological_sex'] as String?;
    final table = who.tableFor(sex);

    // Measurements oldest → newest as (ageYears, heightCm)
    final meas = <(double, double)>[];
    if (dob != null) {
      for (final m in appState.measurements.reversed) {
        final h = (m['stature_height_cm'] as num?)?.toDouble();
        final date = m['recorded_date'] as String?;
        if (h == null || date == null) continue;
        meas.add((ageYearsAt(dob, date), h));
      }
    }

    // Percentile readout for the latest measurement
    String readout = 'No measurements yet — add one below.';
    List<ProjectionPoint> projection = [];
    if (meas.isNotEmpty) {
      final (age, h) = meas.last;
      final bands = interpolateBands(table, age * 12);
      final z = zFromHeight(bands, h);
      final pct = zToPercentile(z);
      readout =
          '${h.toStringAsFixed(1)} cm at ${age.toStringAsFixed(1)}y · ${pct.round()}th percentile (z ${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)})';

      final target = calculateTargetHeight(
        motherHeightCm: (child['mother_height_cm'] as num?)?.toDouble(),
        fatherHeightCm: (child['father_height_cm'] as num?)?.toDouble(),
        motherAge: (child['mother_current_age'] as num?)?.toInt(),
        fatherAge: (child['father_current_age'] as num?)?.toInt(),
        childSex: sex,
      );
      projection = projectGrowth(
        table: table,
        currentAgeYears: age,
        currentHeightCm: h,
        targetZ: target?.correctedZ,
        readinessScore: readiness,
      );
    }

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
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Height-for-age · WHO 2007',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GsColors.measured)),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(readout,
                style:
                    const TextStyle(fontSize: 11.5, color: GsColors.text2)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            width: double.infinity,
            child: CustomPaint(
              painter: _GrowthChartPainter(
                table: table,
                measurements: meas,
                projection: projection,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Shaded: WHO percentile channels (3rd–97th, 15th–85th). '
              'Blue: measured. Dashed gold: estimated trajectory — genetic '
              'target (mid-parental, Zeevi 2024) blended with the current '
              'channel and recent nutrition/activity/sleep. An estimate, '
              'not a medical prediction.',
              style: TextStyle(fontSize: 10, color: GsColors.text3),
            ),
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
  _GrowthChartPainter(
      {required this.table,
      required this.measurements,
      required this.projection});
  final List<List<double>> table;
  final List<(double, double)> measurements; // (ageYears, cm) asc
  final List<ProjectionPoint> projection;

  static const _padL = 34.0, _padR = 8.0, _padT = 8.0, _padB = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    // X range: around the data if present, else the child-age window
    double minAge = table.first[0] / 12, maxAge = table.last[0] / 12;
    if (measurements.isNotEmpty) {
      final firstAge = measurements.first.$1;
      final lastAge = measurements.last.$1;
      final projEnd =
          projection.isEmpty ? lastAge + 2.0 : lastAge + 3.0;
      minAge = math.max(table.first[0] / 12, firstAge - 0.75);
      maxAge = math.min(table.last[0] / 12, math.max(projEnd, lastAge + 2.0));
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
      bandVals.add(interpolateBands(table, age * 12));
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
    final cmStep = (yMaxV - yMinV) > 45 ? 10 : 5;
    for (var cm = (yMinV / cmStep).ceil() * cmStep; cm < yMaxV; cm += cmStep) {
      final y = py(cm.toDouble());
      canvas.drawLine(Offset(_padL, y), Offset(_padL + w, y), gridPaint);
      _text(canvas, '$cm', Offset(2, y - 6), labelStyle);
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

    // ── Percentile channels (smooth) ──
    void fillBetween(List<Offset> top, List<Offset> bottom, Color color) {
      final path = _smoothPath(bottom)
        ..lineTo(top.last.dx, top.last.dy);
      final topRev = top.reversed.toList();
      final topPath = _smoothPath(topRev);
      path.extendWithPath(topPath, Offset.zero);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    fillBetween(bandPts[4], bandPts[0], GsColors.text3.withValues(alpha: 0.12));
    fillBetween(bandPts[3], bandPts[1], GsColors.text3.withValues(alpha: 0.14));

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
    final edgeLabels = ['3', '15', '50', '85', '97'];
    for (var b = 0; b < 5; b++) {
      _text(canvas, edgeLabels[b],
          Offset(bandPts[b].last.dx - 12, bandPts[b].last.dy - 11),
          const TextStyle(fontSize: 8, color: GsColors.text3));
    }

    if (visMeas.isEmpty) {
      _text(
          canvas,
          'No measurements logged yet',
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
      old.table != table;
}

// ── Target height card ──────────────────────────────────────────────

class _TargetHeightCard extends StatelessWidget {
  const _TargetHeightCard({required this.child});
  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
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
          ? const Text(
              'Genetic potential: add mother & father heights in the web '
              "app's Medical tab to unlock the mid-parental target height "
              'and the personalised trajectory.',
              style: TextStyle(fontSize: 12, color: GsColors.estimatedDark))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Genetic target height (adult)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GsColors.estimatedDark)),
                const SizedBox(height: 6),
                Text(
                    '${target.targetHeightCm.toStringAsFixed(1)} cm '
                    '(range ${target.rangeLowCm.toStringAsFixed(1)}–${target.rangeHighCm.toStringAsFixed(1)})',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: GsColors.estimatedDark)),
                const SizedBox(height: 4),
                Text(
                    'Zeevi et al. 2024 method (age-corrected, regression to '
                    'the mean). Traditional Tanner: ${target.tannerMidParentalCm.toStringAsFixed(1)} cm.',
                    style: const TextStyle(
                        fontSize: 10.5, color: GsColors.estimatedDark)),
              ],
            ),
    );
  }
}

// ── Measurement entry ───────────────────────────────────────────────

class _EntryCard extends StatefulWidget {
  const _EntryCard({required this.appState});
  final AppState appState;

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
    final h = double.tryParse(_height.text);
    final w = double.tryParse(_weight.text);
    if (h == null || w == null || h <= 0 || w <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: GsColors.flag,
          content: Text('Enter a valid height and weight')));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState
        .addMeasurement(date: _date, heightCm: h, weightKg: w);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(err == null ? '✅ Measurement logged' : 'Not saved: $err')));
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
          const Text('Log a measurement',
              style: TextStyle(
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
                  decoration: const InputDecoration(
                      labelText: 'Height (cm)', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Weight (kg)', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save measurement'),
          ),
        ],
      ),
    );
  }
}

// ── History list ────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
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
              const Text('Measurement history',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GsColors.measured)),
              Text('${items.length} records',
                  style:
                      const TextStyle(fontSize: 11, color: GsColors.text3)),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Nothing recorded yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: GsColors.text3)),
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
                            content: Text('Could not remove: $err')));
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
