// ══════════════════════════════════════════════════════════════════
// Pediatric visit summary (PDF) - a clean, branded one/two-page
// dossier a parent can hand to a pediatrician. Premium feature.
// Built with the `pdf` package; downloaded via the web Blob helper.
//
// Honesty rules carried over from the app: percentiles are labelled
// as WHO references, the projection/target is a range not a promise,
// and a footer states this is an educational summary, not a
// diagnosis.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../analytics.dart';
import '../app_state.dart';
import '../growth_evidence.dart';
import '../growth_math.dart';
import '../i18n.dart';

const _green = PdfColor.fromInt(0xFF0E2A20);
const _accent = PdfColor.fromInt(0xFF2F6B4F);
const _measured = PdfColor.fromInt(0xFF2A5C8A);
const _gold = PdfColor.fromInt(0xFF9C7A3D);
const _ink = PdfColor.fromInt(0xFF1A2420);
const _muted = PdfColor.fromInt(0xFF6B7570);
const _line = PdfColor.fromInt(0xFFE3E7E5);
const _tint = PdfColor.fromInt(0xFFF2F6F4);
const _white = PdfColor.fromInt(0xFFFFFFFF);

String _fmt(num? v, {int dp = 1}) =>
    v == null ? '-' : v.toDouble().toStringAsFixed(dp);

/// Turn a DB slug like "cold_respiratory" into "Cold respiratory".
String _prettySlug(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '-';
  final s = raw.trim().replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

String _ageString(String? dobStr, [String? atDate]) {
  if (dobStr == null) return '-';
  final dob = DateTime.tryParse(dobStr);
  if (dob == null) return '-';
  final end = atDate != null ? DateTime.tryParse(atDate) ?? DateTime.now()
      : DateTime.now();
  var months = (end.year - dob.year) * 12 + (end.month - dob.month);
  if (end.day < dob.day) months -= 1;
  if (months < 0) months = 0;
  final y = months ~/ 12, m = months % 12;
  return '$y yr${m > 0 ? ' $m mo' : ''}';
}

/// Returns (pdfBytes, error). Gathers the active child's data and lays
/// it out; safe against missing sections.
Future<(Uint8List?, String?)> buildVisitPdf(
    AppState appState, I18n i18n) async {
  final child = appState.activeChildRow;
  if (child == null) return (null, 'No child selected');
  final t = i18n.t;

  try {
    await appState.loadClinicalIfNeeded();
    // Curated evidence (for the plain-language lab lines) + the latest
    // premium AI synthesis, if the family generated one.
    final labEvidence = await GrowthEvidence.load();
    try {
      await appState.loadLatestLabAiReport();
    } catch (_) {}
    final sb = appState.sb;
    final dob = child['date_of_birth'] as String?;
    final sex = child['biological_sex'] as String?;
    final name = (child['name'] as String?)?.trim().isNotEmpty == true
        ? child['name'] as String
        : t('flutter.pdf.child', 'Child');
    final meas = appState.measurements; // newest first

    WeeklyAnalytics? weekly;
    try {
      weekly = await loadWeeklyAnalytics(sb, child);
    } catch (_) {}
    final who = await loadWhoReference();

    // Latest measurement + percentile.
    double? h, w, bmi;
    String? measDate;
    int? pct;
    double? z;
    if (meas.isNotEmpty) {
      final m = meas.first;
      h = (m['stature_height_cm'] as num?)?.toDouble();
      w = (m['mass_weight_kg'] as num?)?.toDouble();
      bmi = (m['calculated_bmi'] as num?)?.toDouble();
      measDate = m['recorded_date'] as String?;
      // BMI: prefer the stored generated column; fall back to a direct
      // calculation so the box is never blank.
      if (bmi == null && h != null && w != null && h > 0) {
        bmi = w / math.pow(h / 100, 2);
      }
      if (h != null && dob != null && measDate != null) {
        final ageM = ageYearsAt(dob, measDate) * 12;
        final bands = who.heightBands(sex, ageM);
        z = zFromHeight(bands, h);
        pct = zToPercentile(z).round();
      }
    }

    // 30-day nutrition averages (over days that have data).
    final since30 =
        localISO(DateTime.now().subtract(const Duration(days: 30)));
    List<Map<String, dynamic>> nutRows = [];
    try {
      nutRows = List<Map<String, dynamic>>.from(await sb
          .from('daily_nutrition')
          .select('total_protein_g, calcium_mg, zinc_mg, fluids_ml')
          .eq('child_id', child['child_id'] as String)
          .gte('log_date', since30));
    } catch (_) {}
    double? avgOf(String col) {
      final vals = [
        for (final r in nutRows)
          if ((r[col] as num?) != null && (r[col] as num) > 0)
            (r[col] as num).toDouble()
      ];
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    final nutDays = nutRows
        .where((r) =>
            ((r['total_protein_g'] as num?) ?? 0) > 0 ||
            ((r['calcium_mg'] as num?) ?? 0) > 0 ||
            ((r['fluids_ml'] as num?) ?? 0) > 0)
        .length;
    final avgProtein = avgOf('total_protein_g');
    final avgCalcium = avgOf('calcium_mg');
    final avgZinc = avgOf('zinc_mg');
    final avgWaterMl = avgOf('fluids_ml');
    final proteinTgt = calcProteinBoostTargetG(dob, w, sex);
    final calciumTgt = calcCalciumTargetMg(dob);
    final zincTgt = calcZincTargetMg(dob, sex);

    final th = calculateTargetHeight(
      motherHeightCm: (child['mother_height_cm'] as num?)?.toDouble(),
      fatherHeightCm: (child['father_height_cm'] as num?)?.toDouble(),
      motherAge: (child['mother_current_age'] as num?)?.toInt(),
      fatherAge: (child['father_current_age'] as num?)?.toInt(),
      childSex: sex,
    );

    final doc = pw.Document(
        title: 'GrowSense visit summary - $name', author: 'GrowSense');

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 34, 36, 42),
      footer: (ctx) => _footer(ctx, t),
      build: (ctx) => [
        _brandHeader(t),
        pw.SizedBox(height: 14),
        _childCard(child, dob, sex, name, t),
        pw.SizedBox(height: 16),
        _sectionTitle(t('flutter.pdf.growth', 'Growth snapshot')),
        pw.SizedBox(height: 8),
        _statRow([
          _stat(t('common.height', 'Height'), h == null ? '-' : '${_fmt(h)} cm',
              measDate ?? '', _measured),
          _stat(t('common.weight', 'Weight'), w == null ? '-' : '${_fmt(w)} kg',
              '', _measured),
          _stat(t('flutter.pdf.bmi', 'BMI'), _fmt(bmi), '', _ink),
          _stat(
              t('flutter.percentile', 'Percentile'),
              pct == null ? '-' : 'P$pct',
              z == null ? '' : 'z ${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}',
              _accent),
        ]),
        pw.SizedBox(height: 8),
        _statRow([
          _stat(
              t('analytics.insight.height_velocity', 'Height velocity'),
              weekly?.velocityCmPerYear == null
                  ? '-'
                  : '${_fmt(weekly!.velocityCmPerYear)} cm/yr',
              weekly?.velocityCmPerYear == null
                  ? t('flutter.velocity.not_enough', 'needs 2+ measurements')
                  : weekly!.velocityLabel,
              _measured),
          _stat(
              t('flutter.pdf.target', 'Target height'),
              th == null ? '-' : '${_fmt(th.targetHeightCm)} cm',
              th == null
                  ? t('flutter.pdf.target_hint', 'add parent heights')
                  : '${_fmt(th.rangeLowCm)} to ${_fmt(th.rangeHighCm)} cm',
              _gold),
          _stat(
              t('flutter.pdf.readiness', '7-day readiness'),
              weekly?.avgScore == null
                  ? '-'
                  : weekly!.avgScore!.round().toString(),
              weekly?.avgScore == null ? '' : t('today.hud.score_suffix', 'of 100'),
              _accent),
          _stat(
              t('analytics.stats.avg_sleep', 'Avg sleep'),
              weekly?.avgSleepHours == null
                  ? '-'
                  : '${_fmt(weekly!.avgSleepHours)} h',
              t('flutter.7d', '7d'),
              _gold),
        ]),
        pw.SizedBox(height: 18),
        _sectionTitle(
            t('flutter.pdf.nutrition', 'Nutrition intake - 30-day average')),
        pw.SizedBox(height: 8),
        if (nutDays == 0)
          _empty(t('flutter.pdf.no_nutrition',
              'No nutrition logged in the last 30 days.'))
        else
          _statRow([
            _stat(
                t('common.protein', 'Protein'),
                avgProtein == null ? '-' : '${_fmt(avgProtein)} g',
                '${t('flutter.pdf.target_short', 'target')} $proteinTgt g',
                _accent),
            _stat(
                t('common.calcium', 'Calcium'),
                avgCalcium == null ? '-' : '${avgCalcium.round()} mg',
                '${t('flutter.pdf.target_short', 'target')} $calciumTgt mg',
                _accent),
            _stat(
                t('common.zinc', 'Zinc'),
                avgZinc == null ? '-' : '${_fmt(avgZinc)} mg',
                '${t('flutter.pdf.target_short', 'target')} $zincTgt mg',
                _accent),
            _stat(
                t('flutter.fluids', 'Fluids'),
                avgWaterMl == null
                    ? '-'
                    : '${_fmt(avgWaterMl / 1000)} L',
                '$nutDays ${t('flutter.pdf.days_logged', 'days logged')}',
                _measured),
          ]),
        pw.SizedBox(height: 18),
        _sectionTitle(t('flutter.pdf.history', 'Measurement history')),
        pw.SizedBox(height: 6),
        _measTable(meas, dob, sex, who, t),
        ..._clinicalSections(appState, t, labEvidence),
        pw.SizedBox(height: 18),
        _disclaimer(t),
      ],
    ));

    return (await doc.save(), null);
  } catch (e) {
    return (null, e.toString());
  }
}

const _logoSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<rect width="24" height="24" rx="6" fill="#2F6B4F"/>'
    '<path d="M4 16 L9 11 L13 15 L20 6" fill="none" stroke="#FFFFFF" '
    'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
    '<circle cx="20" cy="6" r="1.7" fill="#FFFFFF"/></svg>';

pw.Widget _brandHeader(String Function(String, [String?]) t) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: pw.BoxDecoration(
        color: _green, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SvgImage(svg: _logoSvg, width: 30, height: 30),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('GrowSense',
                style: pw.TextStyle(
                    color: _white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(t('flutter.pdf.title', 'Pediatric visit summary'),
                style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFFB7CFC1), fontSize: 10.5)),
          ],
        ),
        pw.Spacer(),
        pw.Text(
            '${t('flutter.pdf.generated', 'Generated')} ${DateTime.now().toIso8601String().split('T').first}',
            style: const pw.TextStyle(
                color: PdfColor.fromInt(0xFF8FB3A2), fontSize: 9)),
      ],
    ),
  );
}

pw.Widget _childCard(Map<String, dynamic> child, String? dob, String? sex,
    String name, String Function(String, [String?]) t) {
  pw.Widget field(String label, String value) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(color: _muted, fontSize: 8.5)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: pw.TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
  final sexLabel = (sex ?? '').toLowerCase() == 'female'
      ? t('common.female', 'Female')
      : t('common.male', 'Male');
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _line, width: 0.5)),
    child: pw.Row(children: [
      field(t('flutter.pdf.name', 'Child'), name),
      field(t('flutter.pdf.age', 'Age'), _ageString(dob)),
      field(t('flutter.pdf.dob', 'Date of birth'), dob ?? '-'),
      field(t('flutter.pdf.sex', 'Sex'), sexLabel),
    ]),
  );
}

pw.Widget _sectionTitle(String text) => pw.Text(text,
    style: pw.TextStyle(
        color: _green, fontSize: 13, fontWeight: pw.FontWeight.bold));

pw.Widget _statRow(List<pw.Widget> boxes) {
  final children = <pw.Widget>[];
  for (var i = 0; i < boxes.length; i++) {
    if (i > 0) children.add(pw.SizedBox(width: 8));
    children.add(pw.Expanded(child: boxes[i]));
  }
  return pw.Row(children: children);
}

pw.Widget _stat(String label, String value, String sub, PdfColor color) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line, width: 0.5),
          borderRadius: pw.BorderRadius.circular(7)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(color: _muted, fontSize: 8)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  color: color, fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (sub.isNotEmpty) ...[
            pw.SizedBox(height: 1),
            pw.Text(sub,
                style: const pw.TextStyle(color: _muted, fontSize: 8)),
          ],
        ],
      ),
    );

pw.Widget _dataTable(List<String> headers, List<List<String>> rows,
    {List<int>? flex}) {
  final f = flex ?? List.filled(headers.length, 1);
  final widths = <int, pw.TableColumnWidth>{
    for (var i = 0; i < headers.length; i++)
      i: pw.FlexColumnWidth(f[i].toDouble()),
  };
  pw.Widget cell(String s, {bool head = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(s,
            style: pw.TextStyle(
                fontSize: 9.5,
                color: head ? _green : _ink,
                fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  return pw.Table(
    columnWidths: widths,
    border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
        bottom: pw.BorderSide(color: _line, width: 0.5)),
    children: [
      pw.TableRow(
          decoration: const pw.BoxDecoration(color: _tint),
          children: [for (final hd in headers) cell(hd, head: true)]),
      for (final r in rows)
        pw.TableRow(children: [for (final c in r) cell(c)]),
    ],
  );
}

pw.Widget _measTable(List<Map<String, dynamic>> meas, String? dob, String? sex,
    WhoReference who, String Function(String, [String?]) t) {
  if (meas.isEmpty) {
    return _empty(t('flutter.pdf.no_meas', 'No measurements recorded yet.'));
  }
  final rows = <List<String>>[];
  for (final m in meas.take(12)) {
    final date = m['recorded_date'] as String?;
    final h = (m['stature_height_cm'] as num?)?.toDouble();
    final w = (m['mass_weight_kg'] as num?)?.toDouble();
    String p = '-';
    if (h != null && dob != null && date != null) {
      final bands = who.heightBands(sex, ageYearsAt(dob, date) * 12);
      p = 'P${zToPercentile(zFromHeight(bands, h)).round()}';
    }
    rows.add([
      date ?? '-',
      _ageString(dob, date),
      h == null ? '-' : _fmt(h),
      w == null ? '-' : _fmt(w),
      p,
    ]);
  }
  return _dataTable([
    t('flutter.pdf.date', 'Date'),
    t('flutter.pdf.age', 'Age'),
    '${t('common.height', 'Height')} (cm)',
    '${t('common.weight', 'Weight')} (kg)',
    t('flutter.pdf.height_pct', 'Ht %ile'),
  ], rows, flex: [3, 2, 2, 2, 2]);
}

List<pw.Widget> _clinicalSections(
    AppState a, String Function(String, [String?]) t, GrowthEvidence ev) {
  final out = <pw.Widget>[];

  if (a.boneAgeAssessments.isNotEmpty) {
    out
      ..add(pw.SizedBox(height: 16))
      ..add(_sectionTitle(t('flutter.pdf.bone_age', 'Bone age history')))
      ..add(pw.SizedBox(height: 6))
      ..add(_dataTable([
        t('flutter.pdf.date', 'Date'),
        t('flutter.pdf.bone_age_m', 'Bone age (mo)'),
        t('flutter.pdf.chron_age_m', 'Chron. age (mo)'),
        t('flutter.pdf.method', 'Method'),
      ], [
        for (final r in a.boneAgeAssessments.take(8))
          [
            (r['study_date'] ?? '-').toString(),
            (r['bone_age_months'] ?? '-').toString(),
            (r['chronological_age_months'] ?? '-').toString(),
            (r['method'] ?? '-').toString(),
          ]
      ], flex: [3, 2, 2, 3]));
  }

  if (a.labResults.isNotEmpty) {
    // Group by analyte (labResults is date-desc → first = latest);
    // order the five focus labs first.
    const order = ['igf1', 'vitamin_d', 'ferritin', 'tsh', 'hemoglobin'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in a.labResults) {
      final k = (r['analyte_name'] as String? ?? '').trim().toLowerCase();
      groups.putIfAbsent(k, () => []).add(r);
    }
    final ordered = groups.values.toList()
      ..sort((x, y) {
        int rank(List<Map<String, dynamic>> g) {
          final k = ev.keyForAnalyteName(g.first['analyte_name'] ?? '');
          final i = k == null ? -1 : order.indexOf(k);
          return i < 0 ? 99 : i;
        }

        return rank(x).compareTo(rank(y));
      });

    double? d(dynamic v) => (v as num?)?.toDouble();
    String statusOf(double v, double? lo, double? hi) {
      if (lo == null && hi == null) return '-';
      if (lo != null && v < lo) return t('flutter.lab.short_low', 'Low');
      if (hi != null && v > hi) return t('flutter.lab.short_high', 'High');
      return t('flutter.lab.short_in', 'In range');
    }

    out
      ..add(pw.SizedBox(height: 16))
      ..add(_sectionTitle(t('flutter.pdf.labs', 'Growth labs')))
      ..add(pw.SizedBox(height: 6));

    // Premium AI synthesis, if the family generated one.
    final report = a.labAiReport?['report'];
    if (report is Map) {
      final headline = report['headline'] as String?;
      final summary = report['parent_summary'] as String?;
      out.add(pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
            color: _tint,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: _line, width: 0.5)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (headline != null && headline.isNotEmpty)
            pw.Text(headline,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _accent)),
          if (summary != null && summary.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(summary,
                style: const pw.TextStyle(
                    fontSize: 8.5, color: _ink, lineSpacing: 1.6)),
          ],
        ]),
      ));
    }

    out.add(_dataTable([
      t('flutter.pdf.analyte', 'Analyte'),
      t('flutter.pdf.latest', 'Latest'),
      t('medical.other_labs.ref_range', 'Reference range'),
      t('flutter.pdf.status', 'Status'),
      'SDS',
    ], [
      for (final g in ordered)
        () {
          final r = g.first;
          final v = d(r['result_value']) ?? 0;
          final lo = d(r['reference_low']);
          final hi = d(r['reference_high']);
          final sds = d(r['sds']);
          return [
            (r['analyte_name'] ?? '-').toString(),
            '${_fmt(v)} ${r['unit'] ?? ''}',
            (lo != null || hi != null)
                ? '${_fmt(lo)}–${_fmt(hi)}'
                : '-',
            statusOf(v, lo, hi),
            sds == null
                ? '-'
                : '${sds >= 0 ? '+' : '−'}${sds.abs().toStringAsFixed(1)}',
          ];
        }()
    ], flex: [3, 2, 3, 2, 1]));

    // Plain-language line per focus analyte (what the family was told).
    final hints = <pw.Widget>[];
    for (final g in ordered) {
      final r = g.first;
      final key = ev.keyForAnalyteName(r['analyte_name'] ?? '');
      if (key == null) continue;
      final v = d(r['result_value']) ?? 0;
      final lo = d(r['reference_low']);
      final hi = d(r['reference_high']);
      final band = (lo == null && hi == null)
          ? null
          : (lo != null && v < lo)
              ? 'low'
              : (hi != null && v > hi)
                  ? 'high'
                  : 'in_range';
      final hint = band == null ? null : ev.analytes[key]?.hintFor(band);
      if (hint == null) continue;
      hints.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Text('• ${r['analyte_name']}: $hint',
            style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ));
    }
    if (hints.isNotEmpty) {
      out
        ..add(pw.SizedBox(height: 6))
        ..add(pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: hints));
    }
  }

  if (a.illnessEvents.isNotEmpty) {
    out
      ..add(pw.SizedBox(height: 16))
      ..add(_sectionTitle(t('flutter.pdf.illness', 'Illness events')))
      ..add(pw.SizedBox(height: 6))
      ..add(_dataTable([
        t('flutter.pdf.start', 'Start'),
        t('flutter.pdf.end', 'End'),
        t('flutter.pdf.type', 'Type'),
      ], [
        for (final e in a.illnessEvents.take(10))
          [
            (e['start_date'] ?? '-').toString(),
            (e['end_date'] ?? '-').toString(),
            _prettySlug((e['illness_type'])?.toString()),
          ]
      ], flex: [3, 3, 4]));
  }

  return out;
}

pw.Widget _empty(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(
          color: _tint, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Text(text,
          style: const pw.TextStyle(color: _muted, fontSize: 9.5)),
    );

pw.Widget _disclaimer(String Function(String, [String?]) t) => pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
          color: _tint,
          borderRadius: pw.BorderRadius.circular(7),
          border: pw.Border.all(color: _line, width: 0.5)),
      child: pw.Text(
          t('flutter.pdf.disclaimer',
              'This summary is an educational aid generated by GrowSense from data logged by the family. Percentiles are illustrative WHO references and the target-height range is a projection, not a diagnosis. Please interpret alongside your clinic\'s official growth chart and clinical judgment.'),
          style: const pw.TextStyle(
              color: _muted, fontSize: 8.5, lineSpacing: 2)),
    );

pw.Widget _footer(pw.Context ctx, String Function(String, [String?]) t) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('growsense.life',
              style: const pw.TextStyle(color: _muted, fontSize: 8)),
          pw.Text(
              '${t('flutter.pdf.page', 'Page')} ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(color: _muted, fontSize: 8)),
        ],
      ),
    );
