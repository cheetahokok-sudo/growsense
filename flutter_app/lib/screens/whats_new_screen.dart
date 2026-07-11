// ══════════════════════════════════════════════════════════════════
// "What's new" — reads assets/release_notes.json (versioned with the
// build) and lists each release with its highlights. Opened by tapping
// the version row in Account.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_meta.dart';
import '../i18n.dart';
import '../theme.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key, required this.i18n});
  final I18n i18n;

  Future<List<dynamic>> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/release_notes.json');
      return (jsonDecode(raw) as Map<String, dynamic>)['releases'] as List;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('flutter.whatsnew.title', "What's new"),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final releases = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                  t('flutter.whatsnew.current', 'You are on {v}',
                      {'v': versionStamp}),
                  style: const TextStyle(fontSize: 12, color: GsColors.text3)),
              const SizedBox(height: 12),
              for (final r in releases)
                _ReleaseCard(release: r as Map<String, dynamic>),
            ],
          );
        },
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});
  final Map<String, dynamic> release;

  @override
  Widget build(BuildContext context) {
    final highlights =
        (release['highlights'] as List?)?.cast<String>() ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: GsColors.accentLight,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('v${release['version']}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GsColors.accentDark)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text((release['title'] as String?) ?? '',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Text((release['date'] as String?) ?? '',
                  style: const TextStyle(fontSize: 10.5, color: GsColors.text3)),
            ],
          ),
          const SizedBox(height: 10),
          for (final h in highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle,
                        size: 14, color: GsColors.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(h,
                        style: const TextStyle(
                            fontSize: 12, height: 1.45, color: GsColors.text2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
