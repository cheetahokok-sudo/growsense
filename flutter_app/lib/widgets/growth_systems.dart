// ══════════════════════════════════════════════════════════════════
// AI cross-lab synthesis (PREMIUM). The per-lab cards + evidence are the
// FREE layer (see the lab detail card); this is the paid intelligence
// that ties the five labs together: a headline, the overall picture,
// patterns across markers, what would sharpen it, and questions for the
// doctor. Plain text, light theme — no diagram (the orbit was cut).
//
// The AI writes prose only; it never emits citations.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../i18n.dart';
import '../theme.dart';

/// Flatten the AI report into a plain-language block a parent can copy,
/// forward, or have read aloud.
String growthReportPlainText(Map<String, dynamic> report,
    {String? disclaimer}) {
  final b = StringBuffer();
  b.writeln('GrowSense — lab interpretation');
  void section(String? s) {
    if (s != null && s.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln(s.trim());
    }
  }

  section(report['headline'] as String?);
  section(report['parent_summary'] as String?);

  final analytes =
      (report['analytes'] as List?)?.whereType<Map>().toList() ?? const [];
  if (analytes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Markers:');
    for (final a in analytes) {
      final name = (a['name'] ?? '').toString();
      final note = (a['value_note'] ?? '').toString();
      final meaning = (a['meaning'] ?? '').toString();
      b.writeln('• $name: $note${meaning.isNotEmpty ? ' $meaning' : ''}');
    }
  }

  final patterns =
      (report['patterns'] as List?)?.whereType<Map>().toList() ?? const [];
  if (patterns.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Patterns across markers:');
    for (final p in patterns) {
      b.writeln('• ${p['reading'] ?? ''}');
    }
  }

  final discuss = (report['clinician_discussion_points'] as List?) ?? const [];
  if (discuss.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Questions for your doctor:');
    for (final d in discuss) {
      b.writeln('• $d');
    }
  }

  final missing = (report['missing_context'] as List?) ?? const [];
  if (missing.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Would sharpen this: ${missing.join(', ')}');
  }

  b
    ..writeln()
    ..writeln(disclaimer ??
        'Educational summary, not a diagnosis. Review with your child\'s doctor.');
  return b.toString();
}

class GrowthSystemsReport extends StatelessWidget {
  const GrowthSystemsReport(
      {super.key, required this.report, required this.i18n});
  final Map<String, dynamic> report;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final headline = report['headline'] as String?;
    final confidence = report['overall_confidence'] as String?;
    final parentSummary = report['parent_summary'] as String?;
    final patterns = (report['patterns'] as List?) ?? const [];
    final missing =
        (report['missing_context'] as List?)?.cast<dynamic>() ?? const [];
    final discuss =
        (report['clinician_discussion_points'] as List?)?.cast<dynamic>() ??
            const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline != null && headline.isNotEmpty)
          Text(headline,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: GsColors.text)),
        if (confidence != null) ...[
          const SizedBox(height: 6),
          _ConfidenceChip(confidence: confidence, i18n: i18n),
        ],

        const SizedBox(height: 10),
        _ReportControls(text: growthReportPlainText(report), i18n: i18n),

        if (parentSummary != null && parentSummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GsColors.accentLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
            ),
            child: Text(parentSummary,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: GsColors.accentDark)),
          ),
        ],

        if (patterns.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('flutter.gs.patterns', 'Patterns across markers'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.measured)),
          for (final p in patterns.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ',
                    style: TextStyle(fontSize: 12, color: GsColors.measured)),
                Expanded(
                    child: Text('${p['reading'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: GsColors.text2,
                            height: 1.4))),
              ]),
            ),
        ],

        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('flutter.gs.missing', 'What would sharpen this'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.estimatedDark)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in missing)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: GsColors.estimatedLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$m',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: GsColors.estimatedDark)),
                ),
            ],
          ),
        ],

        if (discuss.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GsColors.measuredLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('flutter.gs.discuss', 'Questions for your doctor'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GsColors.measuredDark)),
                const SizedBox(height: 4),
                for (final d in discuss)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  fontSize: 12, color: GsColors.measuredDark)),
                          Expanded(
                              child: Text('$d',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: GsColors.measuredDark,
                                      height: 1.4))),
                        ]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence, required this.i18n});
  final String confidence;
  final I18n i18n;
  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final label = switch (confidence) {
      'high' => t('flutter.gs.conf_high', 'High confidence'),
      'moderate' => t('flutter.gs.conf_mod', 'Moderate confidence'),
      _ => t('flutter.gs.conf_low', 'Low confidence'),
    };
    final color = switch (confidence) {
      'high' => GsColors.accent,
      'moderate' => GsColors.measured,
      _ => GsColors.estimated,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}

/// Copy + read-aloud controls for the interpretation. Read-aloud uses the
/// device's built-in text-to-speech (flutter_tts) — on-device, no API or
/// AI-token cost — so a parent can listen while driving.
class _ReportControls extends StatefulWidget {
  const _ReportControls({required this.text, required this.i18n});
  final String text;
  final I18n i18n;

  @override
  State<_ReportControls> createState() => _ReportControlsState();
}

class _ReportControlsState extends State<_ReportControls> {
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _tts
      ..setCompletionHandler(() {
        if (mounted) setState(() => _speaking = false);
      })
      ..setCancelHandler(() {
        if (mounted) setState(() => _speaking = false);
      })
      ..setErrorHandler((_) {
        if (mounted) setState(() => _speaking = false);
      });
    // Configure once, up front (fire-and-forget). Doing this per-tap with
    // awaits before speak() breaks iOS Safari's user-gesture requirement,
    // which was throwing "not available". The report is English, so read
    // it with an English voice regardless of the UI language (avoids a
    // missing-voice failure when the phone has no Thai/other TTS voice).
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.46);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    // Speak first thing in the gesture (no pre-awaits) so iOS Safari keeps
    // the user-activation. flutter_tts.speak returns 1 on success, 0 on
    // failure; reset quietly rather than showing a false error.
    setState(() => _speaking = true);
    try {
      final r = await _tts.speak(widget.text.replaceAll('•', ' '));
      if (r == 0 && mounted) setState(() => _speaking = false);
    } catch (_) {
      if (mounted) setState(() => _speaking = false);
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    _snack(widget.i18n
        .t('flutter.gs.copied', 'Copied — paste into a message to share.'));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Row(children: [
      _btn(Icons.copy_outlined, t('flutter.gs.copy', 'Copy'), _copy),
      const SizedBox(width: 8),
      _btn(
        _speaking ? Icons.stop_rounded : Icons.volume_up_outlined,
        _speaking
            ? t('flutter.gs.stop', 'Stop')
            : t('flutter.gs.listen', 'Listen'),
        _toggleSpeak,
        active: _speaking,
      ),
    ]);
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: active ? GsColors.accent : GsColors.text2,
        side: BorderSide(color: active ? GsColors.accent : GsColors.border2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
