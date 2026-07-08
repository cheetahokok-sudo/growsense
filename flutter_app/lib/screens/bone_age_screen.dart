// ══════════════════════════════════════════════════════════════════
// Bone age intelligence — flagship clinical module.
//
// The real-world gap this fills: parents consult several doctors at
// several hospitals, and each new clinic reads only its own film —
// the serial history that actually shows maturation *trajectory* is
// ignored. This screen keeps every X-ray + radiologist reading in one
// place, plots bone age against calendar age across all studies, and
// offers an AI second opinion per film (bone-age-analysis Edge
// Function — Claude Vision, GP framework, carpal-count-anchored v2
// algorithm, always returns a range).
//
// Statistical framing matches the PWA: delta = bone age − chrono age,
// |delta| ≤ 6 mo within normal; t = delta / sd_months from the report,
// |t| ≥ 2 ≈ p < 0.05 clinically significant.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../growth_math.dart' show ageYearsAt;
import '../i18n.dart';
import '../theme.dart';

String _fmtYM(num months) {
  final m = months.round();
  return '${m ~/ 12}y ${m % 12}m';
}

/// advanced → estimated (gold, ahead of calendar), delayed → measured
/// (blue, behind), within ±6 mo → accent (green).
Color _deltaColor(double deltaMonths) => deltaMonths.abs() <= 6
    ? GsColors.accent
    : (deltaMonths > 0 ? GsColors.estimated : GsColors.measured);

class BoneAgeScreen extends StatefulWidget {
  const BoneAgeScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<BoneAgeScreen> createState() => _BoneAgeScreenState();
}

class _BoneAgeScreenState extends State<BoneAgeScreen> {
  String? _date;
  final _years = TextEditingController();
  final _months = TextEditingController();
  final _sd = TextEditingController();
  final _doctor = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'greulich_pyle';
  bool _busy = false;

  // X-ray picked but not yet uploaded (raw bytes + preview)
  Uint8List? _xrayBytes;
  String? _xrayName;

  @override
  void dispose() {
    for (final c in [_years, _months, _sd, _doctor, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickXray() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _xrayBytes = bytes;
      _xrayName = f.name;
    });
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final years = int.tryParse(_years.text) ?? 0;
    final months = int.tryParse(_months.text) ?? 0;
    final total = years * 12 + months;
    final dob = widget.appState.activeChildRow?['date_of_birth'] as String?;
    if (_date == null || total <= 0 || dob == null) {
      _snack(t('flutter.ba.need_fields', 'Study date and bone age required'));
      return;
    }
    setState(() => _busy = true);

    // Downscale + upload the X-ray first (if picked). Upload failure is
    // non-fatal — the record still saves, same behavior as the PWA.
    String? xrayPath;
    if (_xrayBytes != null) {
      final jpeg = await compute(downscaleXrayJpeg, _xrayBytes!);
      xrayPath = await widget.appState.uploadBoneXray(jpeg);
      if (xrayPath == null && mounted) {
        _snack(t('flutter.ba.upload_failed',
            'X-ray upload failed — record saved without image'));
      }
    }

    final err = await widget.appState.addBoneAge(
      studyDate: _date!,
      boneAgeMonths: total,
      sdMonths: double.tryParse(_sd.text),
      method: _method,
      chronologicalAgeMonths: (ageYearsAt(dob, _date!) * 12 * 10).round() / 10,
      reportDoctor: _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      xrayStoragePath: xrayPath,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _years.clear();
        _months.clear();
        _sd.clear();
        _doctor.clear();
        _notes.clear();
        _date = null;
        _xrayBytes = null;
        _xrayName = null;
      }
    });
    _snack(err ?? t('medical.bone_age.save_btn', 'Bone age record saved'));
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final records = widget.appState.boneAgeAssessments;
        return Scaffold(
          appBar: AppBar(
            title: Text(
                t('flutter.ba.title', 'Bone age intelligence'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (records.isNotEmpty) ...[
                _TimelineCard(
                    records: records, i18n: widget.i18n),
                const SizedBox(height: 12),
              ],
              _entryCard(t),
              const SizedBox(height: 12),
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                      t('flutter.ba.empty',
                          'No bone age studies yet. Add your first radiologist reading — every film you record builds the maturation history no single clinic keeps.'),
                      style: const TextStyle(
                          fontSize: 12, color: GsColors.text3, height: 1.5)),
                )
              else
                for (final r in records) ...[
                  _BoneAgeCard(
                      record: r,
                      appState: widget.appState,
                      i18n: widget.i18n,
                      onDelete: () => _confirmDelete(r)),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> r) async {
    final t = widget.i18n.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
            t('flutter.ba.confirm_delete',
                'Remove this bone age record? The X-ray image is deleted too.'),
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('common.cancel', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('common.remove', 'Remove'),
                  style: const TextStyle(color: GsColors.flag))),
        ],
      ),
    );
    if (ok == true) await widget.appState.deleteBoneAge(r['assessment_id']);
  }

  Widget _entryCard(String Function(String, [String?, Map<String, String>?]) t) {
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
          Text(t('medical.bone_age.label', 'Add a bone age study'),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              t('flutter.ba.entry_sub',
                  "Enter the radiologist's reading and attach the film — readings from any hospital belong in one history."),
              style: const TextStyle(
                  fontSize: 11, color: GsColors.text3, height: 1.4)),
          const SizedBox(height: 12),

          // X-ray picker zone
          GestureDetector(
            onTap: _pickXray,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GsColors.surface2,
                borderRadius: BorderRadius.circular(GsRadius.sm),
                border: Border.all(
                    color: _xrayBytes != null
                        ? GsColors.accent
                        : GsColors.border2),
              ),
              child: _xrayBytes == null
                  ? Row(children: [
                      const Icon(Icons.add_photo_alternate_outlined,
                          size: 20, color: GsColors.text3),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              t('flutter.ba.upload_zone',
                                  'Attach hand X-ray (optional) — enables AI second opinion'),
                              style: const TextStyle(
                                  fontSize: 11.5, color: GsColors.text2))),
                    ])
                  : Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_xrayBytes!,
                            width: 44, height: 44, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_xrayName ?? 'x-ray.jpg',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600))),
                      IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: GsColors.text3),
                          onPressed: () => setState(() {
                                _xrayBytes = null;
                                _xrayName = null;
                              })),
                    ]),
            ),
          ),
          const SizedBox(height: 10),

          _DateButton(
            label: t('medical.bone_age.study_date', 'Study date'),
            value: _date,
            onChanged: (v) => setState(() => _date = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _years,
                    keyboardType: TextInputType.number,
                    decoration: _dec('y'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _months,
                    keyboardType: TextInputType.number,
                    decoration: _dec('m'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _sd,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration:
                        _dec(t('medical.bone_age.sd_label', 'SD (mo)')))),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: _dec(t('common.method', 'Method')),
            items: const [
              DropdownMenuItem(
                  value: 'greulich_pyle',
                  child: Text('Greulich-Pyle (GP)',
                      style: TextStyle(fontSize: 13))),
              DropdownMenuItem(
                  value: 'tw3',
                  child: Text('TW3 (Tanner-Whitehouse)',
                      style: TextStyle(fontSize: 13))),
              DropdownMenuItem(
                  value: 'other',
                  child: Text('Other', style: TextStyle(fontSize: 13))),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 10),
          TextField(
              controller: _doctor,
              decoration: _dec(t('flutter.ba.doctor_hospital',
                  'Doctor / hospital (optional)'))),
          const SizedBox(height: 10),
          TextField(
              controller: _notes,
              decoration:
                  _dec(t('common.notes_optional', 'Notes (optional)'))),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy
                ? t('flutter.saving', 'Saving…')
                : t('medical.bone_age.save_btn', 'Save bone age record')),
          ),
        ],
      ),
    );
  }
}

// ── Maturation timeline — the hero card ────────────────────────────
// Bone age (y) vs chronological age (x) for every study. The identity
// diagonal is "bones match the calendar"; the shaded band is ±12 mo
// (the conventional GP within-normal-limits zone). Serial points make
// the trajectory visible — the thing a single-visit reading can't show.

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.records, required this.i18n});
  final List<Map<String, dynamic>> records;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    // Oldest → newest, only rows with both ages present
    final pts = records
        .where((r) =>
            r['bone_age_months'] != null &&
            r['chronological_age_months'] != null)
        .map((r) => (
              chrono: (r['chronological_age_months'] as num).toDouble(),
              bone: (r['bone_age_months'] as num).toDouble(),
            ))
        .toList()
      ..sort((a, b) => a.chrono.compareTo(b.chrono));
    if (pts.isEmpty) return const SizedBox.shrink();

    final latestDelta = pts.last.bone - pts.last.chrono;
    final trend = _trendText(t, pts);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(
                    t('flutter.ba.timeline_title', 'Maturation timeline'),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _deltaColor(latestDelta).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${latestDelta >= 0 ? '+' : '−'}${latestDelta.abs().toStringAsFixed(0)} mo',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _deltaColor(latestDelta)),
              ),
            ),
          ]),
          Text(
              t('flutter.ba.timeline_sub',
                  '{n} studies · bone age vs calendar age',
                  {'n': '${pts.length}'}),
              style: const TextStyle(fontSize: 11, color: GsColors.text3)),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            width: double.infinity,
            child: CustomPaint(
                painter: _TimelinePainter(pts,
                    axisLabel:
                        t('flutter.ba.axis_calendar', 'calendar age (y)'),
                    yLabel: t('flutter.ba.axis_bone', 'bone age (y)'))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _LegendDot(GsColors.estimated,
                t('flutter.ba.advanced', 'Advanced')),
            const SizedBox(width: 10),
            _LegendDot(
                GsColors.accent, t('flutter.ba.typical', 'Typical ±6 mo')),
            const SizedBox(width: 10),
            _LegendDot(
                GsColors.measured, t('flutter.ba.delayed', 'Delayed')),
          ]),
          if (trend != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GsColors.surface2,
                borderRadius: BorderRadius.circular(GsRadius.sm),
              ),
              child: Text(trend,
                  style: const TextStyle(
                      fontSize: 11.5, color: GsColors.text2, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  String? _trendText(
      String Function(String, [String?, Map<String, String>?]) t,
      List<({double chrono, double bone})> pts) {
    final last = pts.last.bone - pts.last.chrono;
    String interpret(double d) => d.abs() <= 6
        ? t('flutter.ba.interp_typical',
            'Bone maturation matches calendar age.')
        : d < 0
            ? t('flutter.ba.interp_delayed',
                'Bones are younger than the calendar — often more growth runway ahead. Confirm with your pediatrician.')
            : t('flutter.ba.interp_advanced',
                'Bones are ahead of the calendar — growth may finish earlier. Worth discussing timing with your doctor.');
    if (pts.length < 2) return interpret(last);

    final first = pts.first.bone - pts.first.chrono;
    final spanY = (pts.last.chrono - pts.first.chrono) / 12;
    final change = last - first;
    final params = {
      'a': '${first >= 0 ? '+' : '−'}${first.abs().toStringAsFixed(0)}',
      'b': '${last >= 0 ? '+' : '−'}${last.abs().toStringAsFixed(0)}',
      'y': spanY.toStringAsFixed(1),
    };
    String arc;
    if (change.abs() < 3) {
      arc = t('flutter.ba.trend_stable',
          'Gap steady near {b} mo across {y} years of studies.', params);
    } else if (last.abs() < first.abs()) {
      arc = t('flutter.ba.trend_catching',
          'Gap narrowed from {a} to {b} mo over {y} years — maturation is catching up.',
          params);
    } else {
      arc = t('flutter.ba.trend_widening',
          'Gap moved from {a} to {b} mo over {y} years — bring this trend to your next consult.',
          params);
    }
    return '$arc ${interpret(last)}';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: GsColors.text3)),
      ]);
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.pts, {required this.axisLabel, required this.yLabel});
  final List<({double chrono, double bone})> pts;
  final String axisLabel;
  final String yLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 30.0, padR = 12.0, padT = 8.0, padB = 26.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;

    // Shared square domain so the identity line is meaningful:
    // cover both axes' values with breathing room, whole years.
    final all = [
      for (final p in pts) ...[p.chrono, p.bone]
    ];
    var lo = (all.reduce(math.min) / 12).floorToDouble() - 0.5;
    var hi = (all.reduce(math.max) / 12).ceilToDouble() + 0.5;
    if (lo < 0) lo = 0;
    if (hi - lo < 2) hi = lo + 2;

    double x(double months) => padL + (months / 12 - lo) / (hi - lo) * plotW;
    double y(double months) =>
        padT + plotH - (months / 12 - lo) / (hi - lo) * plotH;

    // Gridlines + axis tick labels at whole years
    final grid = Paint()
      ..color = GsColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var yr = lo.ceil(); yr <= hi.floor(); yr++) {
      final gx = x(yr * 12.0), gy = y(yr * 12.0);
      canvas.drawLine(
          Offset(gx, padT), Offset(gx, padT + plotH), grid);
      canvas.drawLine(
          Offset(padL, gy), Offset(padL + plotW, gy), grid);
      _text(canvas, '$yr', Offset(gx - 4, padT + plotH + 4),
          color: GsColors.text3, size: 9);
      _text(canvas, '$yr', Offset(padL - 16, gy - 5),
          color: GsColors.text3, size: 9);
    }
    _text(canvas, axisLabel,
        Offset(padL + plotW / 2 - 34, size.height - 11),
        color: GsColors.text3, size: 8.5);
    canvas.save();
    canvas.translate(1, padT + plotH / 2 + 28);
    canvas.rotate(-math.pi / 2);
    _text(canvas, yLabel, Offset.zero, color: GsColors.text3, size: 8.5);
    canvas.restore();

    // ±12 mo normal band around the identity line
    final bandPath = Path()
      ..moveTo(x(lo * 12), y(lo * 12 + 12))
      ..lineTo(x(hi * 12), y(hi * 12 + 12))
      ..lineTo(x(hi * 12), y(hi * 12 - 12))
      ..lineTo(x(lo * 12), y(lo * 12 - 12))
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padL, padT, plotW, plotH));
    canvas.drawPath(
        bandPath,
        Paint()..color = GsColors.accent.withValues(alpha: 0.07));

    // Identity diagonal (bone age = calendar age)
    final idPaint = Paint()
      ..color = GsColors.text3.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    _dashedLine(canvas, Offset(x(lo * 12), y(lo * 12)),
        Offset(x(hi * 12), y(hi * 12)), idPaint);
    canvas.restore();

    // Trajectory line connecting studies
    if (pts.length > 1) {
      final tp = Paint()
        ..color = GsColors.text2.withValues(alpha: 0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(x(pts.first.chrono), y(pts.first.bone));
      for (final p in pts.skip(1)) {
        path.lineTo(x(p.chrono), y(p.bone));
      }
      canvas.drawPath(path, tp);
    }

    // Study points; latest gets a halo
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final c = _deltaColor(p.bone - p.chrono);
      final center = Offset(x(p.chrono), y(p.bone));
      if (i == pts.length - 1) {
        canvas.drawCircle(
            center, 9, Paint()..color = c.withValues(alpha: 0.18));
      }
      canvas.drawCircle(center, 4.5, Paint()..color = c);
      canvas.drawCircle(
          center,
          4.5,
          Paint()
            ..color = GsColors.surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {required Color color, required double size}) {
    final tp = TextPainter(
        text: TextSpan(
            text: s, style: TextStyle(color: color, fontSize: size)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.pts != pts;
}

// ── Per-study record card ───────────────────────────────────────────

class _BoneAgeCard extends StatefulWidget {
  const _BoneAgeCard(
      {required this.record,
      required this.appState,
      required this.i18n,
      required this.onDelete});
  final Map<String, dynamic> record;
  final AppState appState;
  final I18n i18n;
  final VoidCallback onDelete;

  @override
  State<_BoneAgeCard> createState() => _BoneAgeCardState();
}

class _BoneAgeCardState extends State<_BoneAgeCard> {
  bool _runningAi = false;

  Future<void> _runAi() async {
    setState(() => _runningAi = true);
    final err = await widget.appState.runBoneAgeAI(widget.record);
    if (!mounted) return;
    setState(() => _runningAi = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${widget.i18n.t('flutter.ba.ai_failed', 'AI analysis failed')}: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final r = widget.record;
    final ba = (r['bone_age_months'] as num?)?.toDouble() ?? 0;
    final chrono = (r['chronological_age_months'] as num?)?.toDouble();
    final delta = chrono == null ? null : ba - chrono;
    final sd = (r['sd_months'] as num?)?.toDouble();
    final tScore = (delta != null && sd != null && sd > 0) ? delta / sd : null;
    final xrayPath = r['xray_storage_path'] as String?;
    final aiResult = r['ai_analysis_result'] as Map<String, dynamic>?;

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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (xrayPath != null) ...[
              _XrayThumb(appState: widget.appState, path: xrayPath),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🦴 ${_fmtYM(ba)}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                        '${r['study_date'] ?? ''}'
                        '${r['report_doctor'] != null ? ' · ${r['report_doctor']}' : ''}'
                        ' · ${r['method'] == 'tw3' ? 'TW3' : r['method'] == 'other' ? '—' : 'GP'}',
                        style: const TextStyle(
                            fontSize: 11, color: GsColors.text3)),
                  ]),
            ),
            GestureDetector(
              onTap: widget.onDelete,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child:
                    Icon(Icons.close, size: 16, color: GsColors.text3),
              ),
            ),
          ]),
          if (delta != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              _Stat(
                  value:
                      '${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)} mo',
                  label: t('flutter.ba.delta', 'vs calendar'),
                  color: _deltaColor(delta)),
              _Stat(
                  value: _fmtYM(chrono!),
                  label: t('flutter.chronological_age', 'Calendar age')),
              if (tScore != null)
                _Stat(
                    value:
                        '${tScore >= 0 ? '+' : '−'}${tScore.abs().toStringAsFixed(1)} SD',
                    label: t('flutter.ba.t_score', 't-score'),
                    color: tScore.abs() >= 2 ? GsColors.flag : null),
            ]),
          ],
          if (r['notes'] != null) ...[
            const SizedBox(height: 8),
            Text('${r['notes']}',
                style:
                    const TextStyle(fontSize: 11, color: GsColors.text2)),
          ],

          // AI second opinion
          const SizedBox(height: 10),
          if (xrayPath == null)
            Text(
                t('flutter.ba.no_xray_hint',
                    'Attach an X-ray at entry to enable the AI second opinion.'),
                style: const TextStyle(fontSize: 10.5, color: GsColors.text3))
          else if (_runningAi)
            Row(children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      t('flutter.ba.ai_running',
                          'AI is examining the film with the GP framework…'),
                      style: const TextStyle(
                          fontSize: 11.5, color: GsColors.text2))),
            ])
          else
            OutlinedButton.icon(
              onPressed: _runAi,
              icon: const Icon(Icons.psychology_outlined, size: 16),
              label: Text(
                  aiResult == null
                      ? t('flutter.ba.ai_btn', 'Get AI second opinion')
                      : t('flutter.ba.ai_rerun', 'Re-run AI second opinion'),
                  style: const TextStyle(fontSize: 12)),
            ),
          if (aiResult != null) ...[
            const SizedBox(height: 10),
            _AiPanel(result: aiResult, record: r, i18n: widget.i18n),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color ?? GsColors.text)),
          const SizedBox(height: 1),
          Text(label,
              style: const TextStyle(fontSize: 9.5, color: GsColors.text3)),
        ]),
      );
}

class _XrayThumb extends StatelessWidget {
  const _XrayThumb({required this.appState, required this.path});
  final AppState appState;
  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: appState.xraySignedUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 52,
            height: 52,
            color: GsColors.deepGreen,
            child: url == null
                ? const Icon(Icons.image_outlined,
                    size: 18, color: GsColors.text3)
                : GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: InteractiveViewer(
                              child: Image.network(url))),
                    ),
                    child: Image.network(url, fit: BoxFit.cover),
                  ),
          ),
        );
      },
    );
  }
}

// ── AI second-opinion panel ─────────────────────────────────────────

class _AiPanel extends StatelessWidget {
  const _AiPanel(
      {required this.result, required this.record, required this.i18n});
  final Map<String, dynamic> result;
  final Map<String, dynamic> record;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final est = (result['bone_age_estimate'] as Map?) ?? {};
    final stats = (result['statistical_analysis'] as Map?) ?? {};
    final carpals = (result['carpal_analysis'] as Map?) ?? {};
    final obs = (result['epiphyseal_observations'] as List?) ?? [];

    final best = (est['best_estimate_months'] as num?)?.toDouble();
    final rLo = (est['range_low_months'] as num?)?.toDouble();
    final rHi = (est['range_high_months'] as num?)?.toDouble();
    final confidence = est['confidence'] as String?;
    final sds = (stats['sds_score'] as num?)?.toDouble();
    final sig = stats['clinical_significance'] as String?;
    final docBa = (record['bone_age_months'] as num?)?.toDouble();

    final confColor = switch (confidence) {
      'high' => GsColors.accent,
      'medium' => GsColors.estimated,
      _ => GsColors.flag,
    };
    final sigLabel = switch (sig) {
      'normal' => t('flutter.ba.sig_normal', 'Within normal range'),
      'borderline' => t('flutter.ba.sig_borderline', 'Borderline'),
      _ => t('flutter.ba.sig_significant', 'Significant deviation'),
    };
    final sigColor = switch (sig) {
      'normal' => GsColors.accent,
      'borderline' => GsColors.estimated,
      _ => GsColors.flag,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GsColors.surface2,
        borderRadius: BorderRadius.circular(GsRadius.sm),
        border: Border.all(color: GsColors.border),
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(
                  '🤖 ${t('flutter.ba.ai_title', 'AI second opinion')}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: confColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
                '${confidence ?? 'low'} ${t('flutter.ba.confidence', 'confidence')}',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: confColor)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (best != null)
            _Stat(
                value: _fmtYM(best),
                label: t('flutter.ba.ai_estimate', 'AI estimate')),
          if (rLo != null && rHi != null)
            _Stat(
                value: '${_fmtYM(rLo)}–${_fmtYM(rHi)}',
                label: t('flutter.ba.ai_range', 'Range')),
          if (sds != null)
            _Stat(
                value: '${sds >= 0 ? '+' : '−'}${sds.abs().toStringAsFixed(2)}',
                label: 'SDS',
                color: sigColor),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: sigColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(sigLabel,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: sigColor)),
          ),
        ]),

        // AI vs radiologist
        if (best != null && docBa != null) ...[
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final diff = (best - docBa).abs();
            final note = diff <= 6
                ? t('flutter.ba.cmp_ok',
                    'Within expected inter-rater variability (±6 mo).')
                : diff <= 12
                    ? t('flutter.ba.cmp_review',
                        'Outside typical variability — worth a closer look.')
                    : t('flutter.ba.cmp_large',
                        'Large discrepancy — treat the AI reading with caution.');
            return Text(
                '${t('flutter.ba.cmp_title', 'vs radiologist')}: '
                '${best >= docBa ? '+' : '−'}${diff.toStringAsFixed(0)} mo · $note',
                style: const TextStyle(
                    fontSize: 10.5, color: GsColors.text2, height: 1.4));
          }),
        ],

        // Carpal anchor
        if (carpals['count_visible'] != null) ...[
          const SizedBox(height: 10),
          Text(
              '${t('flutter.ba.carpals', 'Carpal bones (primary anchor)')}: '
              '${carpals['count_visible']}/8'
              '${(carpals['bones_identified'] as List?)?.isNotEmpty == true ? ' · ${(carpals['bones_identified'] as List).join(', ')}' : ''}',
              style: const TextStyle(
                  fontSize: 10.5, color: GsColors.text2, height: 1.4)),
        ],

        // Epiphyseal staging
        if (obs.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final o in obs.cast<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Expanded(
                    flex: 5,
                    child: Text(
                        '${o['bone_group'] ?? ''}'.replaceAll('_', ' '),
                        style: const TextStyle(
                            fontSize: 10, color: GsColors.text3))),
                Expanded(
                    flex: 4,
                    child: Text(
                        '${o['appearance'] ?? ''}'.replaceAll('_', ' '),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GsColors.text2))),
              ]),
            ),
        ],

        if (est['reasoning'] != null) ...[
          const SizedBox(height: 8),
          Text('${est['reasoning']}',
              style: const TextStyle(
                  fontSize: 10.5, color: GsColors.text2, height: 1.5)),
        ],
        const SizedBox(height: 8),
        Text(
            '${result['clinical_caveat'] ?? t('flutter.ba.caveat', 'Educational AI reference only — not a clinical diagnosis.')}',
            style: const TextStyle(
                fontSize: 9.5,
                color: GsColors.text3,
                fontStyle: FontStyle.italic,
                height: 1.4)),
      ]),
    );
  }
}

// ── Small local form helpers (mirrors medical_modules.dart) ─────────

InputDecoration _dec(String label) =>
    InputDecoration(labelText: label, isDense: true);

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value != null ? DateTime.parse(value!) : now,
          firstDate: DateTime(now.year - 18),
          lastDate: now,
        );
        if (picked != null) onChanged(localISO(picked));
      },
      icon: const Icon(Icons.event, size: 16),
      label: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(value ?? label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}
