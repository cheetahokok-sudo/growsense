// ══════════════════════════════════════════════════════════════════
// Report a bug / feedback. Submits a structured row to bug_reports
// (version + anonymized child snapshot auto-attached), with a mailto
// fallback so a report is never lost if the write fails.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_meta.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

class BugReportScreen extends StatefulWidget {
  const BugReportScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _controller = TextEditingController();
  String _category = 'bug';
  String _severity = 'medium';
  bool _busy = false;

  static const _categories = ['bug', 'data_wrong', 'confusing', 'idea'];
  static const _severities = ['low', 'medium', 'high'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _catLabel(String c) {
    final t = widget.i18n.t;
    return switch (c) {
      'data_wrong' => t('flutter.bug.cat.data', 'A number looks wrong'),
      'confusing' => t('flutter.bug.cat.confusing', 'Something is confusing'),
      'idea' => t('flutter.bug.cat.idea', 'An idea / request'),
      _ => t('flutter.bug.cat.bug', 'Something is broken'),
    };
  }

  Future<void> _mailtoFallback(String desc) async {
    final subject = Uri.encodeComponent('GrowSense bug report ($versionShort)');
    final body = Uri.encodeComponent(
        '$desc\n\n---\nVersion: $versionShort\nChannel: $kAppChannel\n'
        'Category: $_category\nSeverity: $_severity');
    await launchUrl(
        Uri.parse('mailto:contact@growsense.life?subject=$subject&body=$body'));
  }

  Future<void> _submit() async {
    final t = widget.i18n.t;
    final desc = _controller.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              t('flutter.bug.empty', 'Please describe what happened first.'))));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState.submitBugReport(
      category: _category,
      severity: _severity,
      description: desc,
      locale: widget.i18n.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('flutter.bug.thanks',
              'Thank you — your report was sent. It helps us fix things.'))));
      Navigator.of(context).pop();
    } else {
      // Write failed — don't lose the report; hand it to email.
      await _mailtoFallback(desc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('flutter.bug.mailto',
                'Opened your email app so the report is not lost.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('flutter.bug.title', 'Report a bug'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
              t('flutter.bug.intro',
                  'Found something off? Tell us what happened. We attach your app version automatically — no personal data beyond your account.'),
              style: const TextStyle(
                  fontSize: 12.5, height: 1.5, color: GsColors.text2)),
          const SizedBox(height: 16),
          Text(t('flutter.bug.what', 'What kind of thing is it?'),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _categories)
                _Chip(
                    label: _catLabel(c),
                    selected: c == _category,
                    onTap: () => setState(() => _category = c)),
            ],
          ),
          const SizedBox(height: 18),
          Text(t('flutter.bug.severity', 'How much does it affect you?'),
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in _severities) ...[
                _Chip(
                    label: switch (s) {
                      'low' => t('flutter.bug.sev.low', 'Minor'),
                      'high' => t('flutter.bug.sev.high', 'Blocking'),
                      _ => t('flutter.bug.sev.medium', 'Annoying'),
                    },
                    selected: s == _severity,
                    onTap: () => setState(() => _severity = s)),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: t('flutter.bug.hint',
                  'What did you do, and what happened? The more detail, the faster we can fix it.'),
              filled: true,
              fillColor: GsColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GsRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              t('flutter.bug.attached', 'Attached automatically: {v} · {ch}',
                  {'v': versionShort, 'ch': kAppChannel}),
              style: const TextStyle(fontSize: 10.5, color: GsColors.text3)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46)),
            child: Text(_busy
                ? t('flutter.bug.sending', 'Sending…')
                : t('flutter.bug.send', 'Send report')),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => _mailtoFallback(_controller.text.trim()),
              child: Text(t('flutter.bug.email_instead', 'Or email us instead'),
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? GsColors.accentLight : GsColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? GsColors.accent.withValues(alpha: 0.4)
                  : GsColors.border2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? GsColors.accent : GsColors.text2)),
      ),
    );
  }
}
